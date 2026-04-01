// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { State, IAutocallEngine } from "../interfaces/IAutocallEngine.sol";
import { IHedgeManager } from "../interfaces/IHedgeManager.sol";
import { ICREConsumer, PricingResult } from "../interfaces/ICREConsumer.sol";
import { PricingParams } from "../interfaces/IOptionPricer.sol";
import { IIssuanceGate } from "../interfaces/IIssuanceGate.sol";
import { ICouponCalculator } from "../interfaces/ICouponCalculator.sol";
import { IVolOracle } from "../interfaces/IVolOracle.sol";
import { ICarryEngine } from "../interfaces/ICarryEngine.sol";
import { ISablierStream } from "../interfaces/ISablierStream.sol";
import { NoteToken } from "./NoteToken.sol";

/// @notice Minimal interface for reading latest verified prices.
interface IPriceFeed {
    function getLatestPrice(bytes32 feedId) external view returns (int192 price, uint32 timestamp);
}

/// @title AutocallEngine
/// @notice State machine with 12 states for Phoenix Autocall worst-of notes.
///         Handles create, observe (autocall/coupon/KI), and settle flows.
contract AutocallEngine is IAutocallEngine, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Roles
    // ----------------------------------------------------------------
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------
    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_OBSERVATIONS = 6;
    uint256 public constant OBS_INTERVAL_DAYS = 30;
    uint16 public constant COUPON_BARRIER_BPS = 7_000; // 70%
    uint16 public constant AUTOCALL_TRIGGER_BPS = 10_000; // 100%
    uint16 public constant STEP_DOWN_BPS = 200; // 2% per obs
    uint16 public constant KI_BARRIER_BPS = 7_000; // 70%
    uint256 public constant MATURITY_DAYS = 180;
    uint256 public constant PRICE_MAX_STALENESS = 24 hours; // per spec section 15
    uint256 public constant KI_SETTLE_DEADLINE = 7 days; // holder must choose within 7 days

    // ----------------------------------------------------------------
    // Note structure
    // ----------------------------------------------------------------
    struct Note {
        address[] basket;
        uint256 notional;
        address holder;
        State state;
        uint8 observations;
        uint256 memoryCoupon; // accumulated unpaid base coupons (USDC amount)
        uint256 totalCouponBps; // fixed at issuance
        uint256 baseCouponBps; // fixed at issuance
        uint256 createdAt;
        uint256 maturityDate;
        uint256 lastObservationTime; // enforce minimum interval between observations
        uint256 kiSettleStartTime; // when KI settlement window opened
        int256[] initialPrices; // initial spot prices for perf calc
    }

    // ----------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------
    mapping(bytes32 => Note) internal _notes;
    uint256 public noteCount;
    bytes32[] public noteIds;

    IERC20 public immutable USDC;
    IHedgeManager public immutable HEDGE_MANAGER;
    ICREConsumer public immutable CRE_CONSUMER;
    IIssuanceGate public immutable ISSUANCE_GATE;
    ICouponCalculator public immutable COUPON_CALCULATOR;
    IPriceFeed public immutable PRICE_FEED;
    IVolOracle public immutable VOL_ORACLE;
    ICarryEngine public immutable CARRY_ENGINE;
    NoteToken public immutable NOTE_TOKEN;

    /// @notice Sablier coupon streaming adapter (set post-deploy, optional)
    ISablierStream public sablierStream;

    /// @notice Maps xStock token address -> Pyth/Chainlink feed ID
    mapping(address => bytes32) public feedIds;

    /// @notice Testnet mode: skip issuance gate CRE check
    bool public testnetMode;

    function setTestnetMode(bool _testnet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        testnetMode = _testnet;
    }

    /// @notice Set the Sablier coupon streaming adapter. Admin only.
    function setSablierStream(address _sablierStream) external onlyRole(DEFAULT_ADMIN_ROLE) {
        sablierStream = ISablierStream(_sablierStream);
    }

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------
    event NoteCreated(bytes32 indexed noteId, address indexed holder, uint256 notional);
    event RequestPricing(bytes32 indexed noteId, address[] basket, uint256 notional);
    event NoteStateChanged(bytes32 indexed noteId, State from, State to);
    event CouponPaid(bytes32 indexed noteId, uint256 amount, uint256 memoryPaid);
    event CouponMissed(bytes32 indexed noteId, uint256 memoryAccumulated);
    event CouponStreamed(bytes32 indexed noteId, uint256 streamId, uint256 amount);
    event NoteAutocalled(bytes32 indexed noteId, uint8 observation);
    event NoteSettled(bytes32 indexed noteId, uint256 payout, bool kiPhysical);
    event EmergencyPaused(bytes32 indexed noteId);
    event EmergencyResumed(bytes32 indexed noteId);
    event NoteCancelled(bytes32 indexed noteId);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------
    error InvalidState(State current, State expected);
    error InvalidTransition(State from, State to);
    error OnlyHolder();
    error InvalidBasket();
    error IssuanceNotApproved(string reason);
    error NoteNotFound();
    error ObservationTooEarly(uint256 earliest, uint256 current);
    error StalePriceFeed(bytes32 feedId, uint32 feedTimestamp);

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------
    constructor(
        address admin,
        address _usdc,
        address _hedgeManager,
        address _creConsumer,
        address _issuanceGate,
        address _couponCalculator,
        address _priceFeed,
        address _volOracle,
        address _carryEngine,
        address _noteToken
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        USDC = IERC20(_usdc);
        HEDGE_MANAGER = IHedgeManager(_hedgeManager);
        CRE_CONSUMER = ICREConsumer(_creConsumer);
        ISSUANCE_GATE = IIssuanceGate(_issuanceGate);
        COUPON_CALCULATOR = ICouponCalculator(_couponCalculator);
        PRICE_FEED = IPriceFeed(_priceFeed);
        VOL_ORACLE = IVolOracle(_volOracle);
        CARRY_ENGINE = ICarryEngine(_carryEngine);
        NOTE_TOKEN = NoteToken(_noteToken);
    }

    /// @notice Set the Chainlink feed ID for an xStock token. Admin only.
    function setFeedId(address xStock, bytes32 feedId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feedIds[xStock] = feedId;
    }

    /// @notice Batch-set feed IDs for multiple xStocks.
    function setFeedIds(address[] calldata xStocks, bytes32[] calldata _feedIds)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(xStocks.length == _feedIds.length, "length mismatch");
        for (uint256 i = 0; i < xStocks.length; i++) {
            feedIds[xStocks[i]] = _feedIds[i];
        }
    }

    // ----------------------------------------------------------------
    // Create
    // ----------------------------------------------------------------

    /// @inheritdoc IAutocallEngine
    function createNote(address[] calldata basket, uint256 notional, address holder)
        external
        override
        onlyRole(VAULT_ROLE)
        returns (bytes32 noteId)
    {
        if (basket.length < 2 || basket.length > 5) revert InvalidBasket();
        require(notional > 0, "zero notional");

        noteId = keccak256(abi.encodePacked(basket, notional, holder, block.timestamp, noteCount));
        require(_notes[noteId].createdAt == 0, "duplicate noteId");

        Note storage note = _notes[noteId];
        note.basket = basket;
        note.notional = notional;
        note.holder = holder;
        note.state = State.Created;
        note.createdAt = block.timestamp;
        note.maturityDate = block.timestamp + (MATURITY_DAYS * 1 days);

        noteIds.push(noteId);
        noteCount++;

        // Auto-register note params on CREConsumer so CRE pricing can be accepted
        CRE_CONSUMER.registerNoteParams(
            noteId,
            PricingParams({
                basket: basket,
                kiBarrierBps: KI_BARRIER_BPS,
                couponBarrierBps: COUPON_BARRIER_BPS,
                autocallTriggerBps: AUTOCALL_TRIGGER_BPS,
                stepDownBps: STEP_DOWN_BPS,
                maturityDays: MATURITY_DAYS,
                numObservations: MAX_OBSERVATIONS
            })
        );

        emit NoteCreated(noteId, holder, notional);
        // CRE workflow triggers on this event to start pricing
        emit RequestPricing(noteId, basket, notional);
    }

    // ----------------------------------------------------------------
    // Pricing callback: CREATED -> PRICED
    // ----------------------------------------------------------------

    /// @notice Called after CRE pricing is accepted. Transitions CREATED -> PRICED.
    ///         Reads actual vol from VolOracle and carry rate from CarryEngine
    ///         to compute dynamic safety margin and carry enhancement per spec section 5.
    function priceNote(bytes32 noteId, int256[] calldata initialPrices) external onlyRole(KEEPER_ROLE) {
        Note storage note = _notes[noteId];
        _requireState(noteId, State.Created);

        PricingResult memory pricing = CRE_CONSUMER.getAcceptedPricing(noteId);

        // Fetch average vol across basket for dynamic safety margin
        uint256 avgVol = 0;
        for (uint256 i = 0; i < note.basket.length; i++) {
            avgVol += VOL_ORACLE.getVol(note.basket[i]);
        }
        avgVol = avgVol / note.basket.length;

        // Fetch carry rate for carry enhancement
        uint256 carryRate = CARRY_ENGINE.getTotalCarryRate();

        (uint256 baseBps, , uint256 totalBps) =
            COUPON_CALCULATOR.calculateCoupon(pricing.putPremiumBps, avgVol, carryRate);

        note.baseCouponBps = baseBps;
        note.totalCouponBps = totalBps;
        note.initialPrices = initialPrices;

        _transition(noteId, State.Priced);
    }

    /// @notice Direct pricing for testnet — keeper provides premium directly.
    ///         Bypasses CRE for testing. In production, use priceNote() with CRE.
    function priceNoteDirect(
        bytes32 noteId,
        int256[] calldata initialPrices,
        uint256 putPremiumBps
    ) external onlyRole(KEEPER_ROLE) {
        Note storage note = _notes[noteId];
        _requireState(noteId, State.Created);

        // Fetch vol for safety margin
        uint256 avgVol = 0;
        for (uint256 i = 0; i < note.basket.length; i++) {
            avgVol += VOL_ORACLE.getVol(note.basket[i]);
        }
        avgVol = note.basket.length > 0 ? avgVol / note.basket.length : 0;

        uint256 carryRate = CARRY_ENGINE.getTotalCarryRate();

        (uint256 baseBps, , uint256 totalBps) =
            COUPON_CALCULATOR.calculateCoupon(putPremiumBps, avgVol, carryRate);

        note.baseCouponBps = baseBps;
        note.totalCouponBps = totalBps;
        note.initialPrices = initialPrices;

        _transition(noteId, State.Priced);
    }

    // ----------------------------------------------------------------
    // Activate: PRICED -> ACTIVE (requires issuance gate)
    // ----------------------------------------------------------------

    /// @notice Transitions PRICED -> ACTIVE after issuance gate approval (INV-6).
    ///         Opens the delta-neutral hedge (spot + perps) per spec section 10.
    function activateNote(bytes32 noteId) external onlyRole(KEEPER_ROLE) {
        Note storage note = _notes[noteId];
        _requireState(noteId, State.Priced);

        // Issuance gate check (skip CRE pricing check in testnet mode)
        if (!testnetMode) {
            (bool approved, string memory reason) =
                ISSUANCE_GATE.checkIssuance(noteId, note.notional, note.basket);
            if (!approved) revert IssuanceNotApproved(reason);
        }

        // Open hedge (HedgeManager handles testnet mode internally)
        USDC.safeIncreaseAllowance(address(HEDGE_MANAGER), note.notional);
        HEDGE_MANAGER.openHedge(noteId, note.basket, note.notional);

        // Update issuance gate counters
        ISSUANCE_GATE.noteActivated(note.notional);

        // Set observation time so first observe must wait OBS_INTERVAL_DAYS
        note.lastObservationTime = block.timestamp;

        _transition(noteId, State.Active);
    }

    // ----------------------------------------------------------------
    // Observe: ACTIVE -> OBSERVATION_PENDING -> (coupon/autocall/maturity)
    // ----------------------------------------------------------------

    /// @inheritdoc IAutocallEngine
    function observe(bytes32 noteId) external override nonReentrant {
        Note storage note = _notes[noteId];
        if (note.state != State.Active && note.state != State.ObservationPending) {
            revert InvalidState(note.state, State.Active);
        }

        // Enforce minimum interval between observations (~30 days)
        uint256 earliest = note.lastObservationTime + (OBS_INTERVAL_DAYS * 1 days);
        if (note.lastObservationTime > 0 && block.timestamp < earliest) {
            revert ObservationTooEarly(earliest, block.timestamp);
        }
        note.lastObservationTime = block.timestamp;

        // Move to observation pending if not already
        if (note.state == State.Active) {
            _transition(noteId, State.ObservationPending);
        }

        // 1. Get worst-of performance (also checks price staleness)
        uint256 worstPerfBps = _getWorstPerformance(note);

        // 2. Check autocall trigger (with step-down)
        // Obs 1: trigger=100%, Obs 2: 98%, Obs 3: 96%, ..., Obs 6: 90%
        uint256 triggerBps = AUTOCALL_TRIGGER_BPS - (uint256(STEP_DOWN_BPS) * note.observations);

        // Increment observations AFTER trigger calc to avoid off-by-one
        note.observations++;
        if (worstPerfBps >= triggerBps) {
            // Autocalled: pay all coupons (current + memory) then settle
            _payCoupon(noteId, note, true);
            _transition(noteId, State.Autocalled);
            emit NoteAutocalled(noteId, note.observations);
            _settleAutocall(noteId, note);
            return;
        }

        // 3. Check coupon barrier
        if (worstPerfBps >= COUPON_BARRIER_BPS) {
            _payCoupon(noteId, note, true);
        } else {
            // Coupon missed -- accumulate base coupon as memory
            uint256 baseCouponAmount = COUPON_CALCULATOR.calculateCouponAmount(
                note.notional, note.baseCouponBps, OBS_INTERVAL_DAYS
            );
            note.memoryCoupon += baseCouponAmount;
            emit CouponMissed(noteId, note.memoryCoupon);
        }

        // 4. Check if last observation -> maturity
        if (note.observations >= MAX_OBSERVATIONS) {
            _transition(noteId, State.MaturityCheck);
            _handleMaturity(noteId, note, worstPerfBps);
        } else {
            // Return to active for next observation
            _transition(noteId, State.Active);
        }
    }

    // ----------------------------------------------------------------
    // KI Settlement: holder's choice (section 11)
    // ----------------------------------------------------------------

    /// @inheritdoc IAutocallEngine
    function settleKi(bytes32 noteId, bool preferPhysical) external override nonReentrant {
        Note storage note = _notes[noteId];
        _requireState(noteId, State.KISettle);
        if (msg.sender != note.holder) revert OnlyHolder();

        _cancelAllNoteStreams(noteId);
        uint256 recovered = HEDGE_MANAGER.closeHedge(noteId);
        uint256 worstPerfBps = _getWorstPerformance(note);

        if (preferPhysical) {
            USDC.safeTransfer(note.holder, recovered);
            emit NoteSettled(noteId, recovered, true);
        } else {
            uint256 cashValue = (note.notional * worstPerfBps) / BPS;
            uint256 payout = cashValue < recovered ? cashValue : recovered;
            USDC.safeTransfer(note.holder, payout);
            emit NoteSettled(noteId, payout, false);
        }

        _burnNoteToken(noteId, note);
        _transition(noteId, State.Settled);
    }

    /// @notice Admin force-settle KI if holder doesn't choose within deadline.
    ///         Defaults to cash settlement to protect the holder.
    function forceSettleKi(bytes32 noteId) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        Note storage note = _notes[noteId];
        _requireState(noteId, State.KISettle);
        require(
            block.timestamp > note.kiSettleStartTime + KI_SETTLE_DEADLINE,
            "KI settle deadline not reached"
        );

        _cancelAllNoteStreams(noteId);
        uint256 recovered = HEDGE_MANAGER.closeHedge(noteId);
        uint256 worstPerfBps = _getWorstPerformance(note);
        uint256 cashValue = (note.notional * worstPerfBps) / BPS;
        uint256 payout = cashValue < recovered ? cashValue : recovered;
        USDC.safeTransfer(note.holder, payout);

        _burnNoteToken(noteId, note);
        _transition(noteId, State.Settled);
        emit NoteSettled(noteId, payout, false);
    }

    // ----------------------------------------------------------------
    // Emergency: ACTIVE -> EMERGENCY_PAUSED -> ACTIVE
    // ----------------------------------------------------------------

    function emergencyPause(bytes32 noteId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _requireState(noteId, State.Active);
        _transition(noteId, State.EmergencyPaused);
        emit EmergencyPaused(noteId);
    }

    function emergencyResume(bytes32 noteId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _requireState(noteId, State.EmergencyPaused);
        _transition(noteId, State.Active);
        emit EmergencyResumed(noteId);
    }

    // ----------------------------------------------------------------
    // Cancel: CREATED/PRICED -> CANCELLED
    // ----------------------------------------------------------------

    function cancelNote(bytes32 noteId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Note storage note = _notes[noteId];
        if (note.state != State.Created && note.state != State.Priced) {
            revert InvalidTransition(note.state, State.Cancelled);
        }
        _transition(noteId, State.Cancelled);
        emit NoteCancelled(noteId);
    }

    // ----------------------------------------------------------------
    // View
    // ----------------------------------------------------------------

    /// @inheritdoc IAutocallEngine
    function getState(bytes32 noteId) external view override returns (State) {
        return _notes[noteId].state;
    }

    /// @inheritdoc IAutocallEngine
    function getNoteCount() external view override returns (uint256) {
        return noteCount;
    }

    function getNote(bytes32 noteId)
        external
        view
        returns (
            address[] memory basket,
            uint256 notional,
            address holder,
            State state,
            uint8 observations,
            uint256 memoryCoupon,
            uint256 totalCouponBps,
            uint256 createdAt,
            uint256 maturityDate
        )
    {
        Note storage note = _notes[noteId];
        return (
            note.basket,
            note.notional,
            note.holder,
            note.state,
            note.observations,
            note.memoryCoupon,
            note.totalCouponBps,
            note.createdAt,
            note.maturityDate
        );
    }

    /// @notice Get computed status for frontend display
    function getNoteStatus(bytes32 noteId) external view returns (
        State state,
        uint8 observations,
        uint256 nextObservationTime,
        uint256 currentTriggerBps,
        uint256 couponPerObsBps
    ) {
        Note storage note = _notes[noteId];
        state = note.state;
        observations = note.observations;
        nextObservationTime = note.lastObservationTime + (OBS_INTERVAL_DAYS * 1 days);
        currentTriggerBps = AUTOCALL_TRIGGER_BPS - (uint256(STEP_DOWN_BPS) * note.observations);
        couponPerObsBps = note.totalCouponBps;
    }

    // ----------------------------------------------------------------
    // Internal: state transitions
    // ----------------------------------------------------------------

    function _transition(bytes32 noteId, State to) internal {
        Note storage note = _notes[noteId];
        State from = note.state;
        if (!_isValidTransition(from, to)) {
            revert InvalidTransition(from, to);
        }
        note.state = to;
        emit NoteStateChanged(noteId, from, to);
    }

    function _requireState(bytes32 noteId, State expected) internal view {
        State current = _notes[noteId].state;
        if (current != expected) revert InvalidState(current, expected);
    }

    /// @dev INV-4: only allowed transitions
    function _isValidTransition(State from, State to) internal pure returns (bool) {
        if (from == State.Created && to == State.Priced) return true;
        if (from == State.Created && to == State.Cancelled) return true;
        if (from == State.Priced && to == State.Active) return true;
        if (from == State.Priced && to == State.Cancelled) return true;
        if (from == State.Active && to == State.ObservationPending) return true;
        if (from == State.Active && to == State.EmergencyPaused) return true;
        if (from == State.ObservationPending && to == State.Autocalled) return true;
        if (from == State.ObservationPending && to == State.Active) return true;
        if (from == State.ObservationPending && to == State.MaturityCheck) return true;
        if (from == State.Autocalled && to == State.Settled) return true;
        if (from == State.MaturityCheck && to == State.NoKISettle) return true;
        if (from == State.MaturityCheck && to == State.KISettle) return true;
        if (from == State.NoKISettle && to == State.Settled) return true;
        if (from == State.KISettle && to == State.Settled) return true;
        if (from == State.Settled && to == State.Rolled) return true;
        if (from == State.EmergencyPaused && to == State.Active) return true;
        return false;
    }

    // ----------------------------------------------------------------
    // Internal: observation helpers
    // ----------------------------------------------------------------

    /// @notice Calculate the worst-of performance across the basket.
    ///         perf_i = currentPrice_i / initialPrice_i * BPS
    ///         Returns min(perf_i) in basis points.
    function _getWorstPerformance(Note storage note) internal view returns (uint256) {
        uint256 worst = type(uint256).max;
        for (uint256 i = 0; i < note.basket.length; i++) {
            require(note.initialPrices.length > i && note.initialPrices[i] > 0, "missing initial price");

            bytes32 feedId = feedIds[note.basket[i]];
            require(feedId != bytes32(0), "feed not configured");

            (int192 currentPrice, uint32 feedTimestamp) = PRICE_FEED.getLatestPrice(feedId);
            require(currentPrice > 0, "invalid current price");
            if (block.timestamp - feedTimestamp > PRICE_MAX_STALENESS) {
                revert StalePriceFeed(feedId, feedTimestamp);
            }

            // perf = currentPrice / initialPrice * BPS
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 perf = (uint256(int256(currentPrice)) * BPS) / uint256(note.initialPrices[i]);
            if (perf < worst) {
                worst = perf;
            }
        }
        return worst;
    }

    function _payCoupon(bytes32 noteId, Note storage note, bool includeMemory) internal {
        uint256 couponAmount =
            COUPON_CALCULATOR.calculateCouponAmount(note.notional, note.totalCouponBps, OBS_INTERVAL_DAYS);

        uint256 memoryPaid = 0;
        if (includeMemory && note.memoryCoupon > 0) {
            memoryPaid = note.memoryCoupon;
            note.memoryCoupon = 0;
        }

        // Pay memory coupon directly (lump sum — these are past-due amounts)
        if (memoryPaid > 0) {
            USDC.safeTransfer(note.holder, memoryPaid);
        }

        // Stream current coupon via Sablier (if configured), else direct transfer
        if (couponAmount > 0) {
            if (address(sablierStream) != address(0)) {
                USDC.forceApprove(address(sablierStream), couponAmount);
                uint256 streamId = sablierStream.startCouponStream(
                    noteId,
                    note.holder,
                    couponAmount,
                    block.timestamp,
                    block.timestamp + (OBS_INTERVAL_DAYS * 1 days)
                );
                emit CouponStreamed(noteId, streamId, couponAmount);
            } else {
                USDC.safeTransfer(note.holder, couponAmount);
            }
        }

        emit CouponPaid(noteId, couponAmount, memoryPaid);
    }

    /// @notice Cancel all active Sablier streams for a note on settlement.
    ///         Refunded USDC stays in SablierStream and can be recovered by admin.
    function _cancelAllNoteStreams(bytes32 noteId) internal {
        if (address(sablierStream) != address(0)) {
            sablierStream.cancelAllNoteStreams(noteId);
        }
    }

    function _settleAutocall(bytes32 noteId, Note storage note) internal {
        _cancelAllNoteStreams(noteId);
        uint256 recovered = HEDGE_MANAGER.closeHedge(noteId);
        uint256 payout = note.notional < recovered ? note.notional : recovered;
        USDC.safeTransfer(note.holder, payout);

        _burnNoteToken(noteId, note);
        _transition(noteId, State.Settled);
        emit NoteSettled(noteId, payout, false);
    }

    function _handleMaturity(bytes32 noteId, Note storage note, uint256 worstPerfBps) internal {
        if (worstPerfBps < KI_BARRIER_BPS) {
            // KI breached at maturity (European)
            note.kiSettleStartTime = block.timestamp;
            _transition(noteId, State.KISettle);
        } else {
            // No KI -- settle at par + remaining coupons
            _transition(noteId, State.NoKISettle);
            _settleNoKi(noteId, note);
        }
    }

    function _settleNoKi(bytes32 noteId, Note storage note) internal {
        _cancelAllNoteStreams(noteId);

        // Pay out any accumulated memory coupons before settling
        if (note.memoryCoupon > 0) {
            uint256 memoryPaid = note.memoryCoupon;
            note.memoryCoupon = 0;
            USDC.safeTransfer(note.holder, memoryPaid);
            emit CouponPaid(noteId, 0, memoryPaid);
        }

        uint256 recovered = HEDGE_MANAGER.closeHedge(noteId);
        uint256 payout = note.notional < recovered ? note.notional : recovered;
        USDC.safeTransfer(note.holder, payout);

        _burnNoteToken(noteId, note);
        _transition(noteId, State.Settled);
        emit NoteSettled(noteId, payout, false);
    }

    /// @notice Burn NoteToken + update issuance gate on settlement.
    function _burnNoteToken(bytes32 noteId, Note storage note) internal {
        if (address(NOTE_TOKEN) != address(0)) {
            uint256 tokenBal = NOTE_TOKEN.balanceOf(note.holder, uint256(noteId));
            if (tokenBal > 0) {
                NOTE_TOKEN.burn(note.holder, noteId, tokenBal);
            }
        }
        // Update issuance gate counters
        ISSUANCE_GATE.noteSettled(note.notional);
    }
}
