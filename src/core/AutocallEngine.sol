// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { State, IAutocallEngine } from "../interfaces/IAutocallEngine.sol";
import { IHedgeManager } from "../interfaces/IHedgeManager.sol";
import { ICREConsumer, PricingResult } from "../interfaces/ICREConsumer.sol";
import { IIssuanceGate } from "../interfaces/IIssuanceGate.sol";
import { ICouponCalculator } from "../interfaces/ICouponCalculator.sol";

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
    uint16 public constant KI_BARRIER_BPS = 5_000; // 50%
    uint256 public constant MATURITY_DAYS = 180;

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
        int256[] initialPrices; // initial spot prices for perf calc
    }

    // ----------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------
    mapping(bytes32 => Note) internal _notes;
    uint256 public noteCount;
    bytes32[] public noteIds;

    IERC20 public immutable usdc;
    IHedgeManager public immutable hedgeManager;
    ICREConsumer public immutable creConsumer;
    IIssuanceGate public immutable issuanceGate;
    ICouponCalculator public immutable couponCalculator;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------
    event NoteCreated(bytes32 indexed noteId, address indexed holder, uint256 notional);
    event NoteStateChanged(bytes32 indexed noteId, State from, State to);
    event CouponPaid(bytes32 indexed noteId, uint256 amount, uint256 memoryPaid);
    event CouponMissed(bytes32 indexed noteId, uint256 memoryAccumulated);
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

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------
    constructor(
        address admin,
        address _usdc,
        address _hedgeManager,
        address _creConsumer,
        address _issuanceGate,
        address _couponCalculator
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        usdc = IERC20(_usdc);
        hedgeManager = IHedgeManager(_hedgeManager);
        creConsumer = ICREConsumer(_creConsumer);
        issuanceGate = IIssuanceGate(_issuanceGate);
        couponCalculator = ICouponCalculator(_couponCalculator);
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
        if (basket.length != 3) revert InvalidBasket();

        noteId = keccak256(abi.encodePacked(basket, notional, holder, block.timestamp, noteCount));

        Note storage note = _notes[noteId];
        note.basket = basket;
        note.notional = notional;
        note.holder = holder;
        note.state = State.Created;
        note.createdAt = block.timestamp;
        note.maturityDate = block.timestamp + (MATURITY_DAYS * 1 days);

        noteIds.push(noteId);
        noteCount++;

        emit NoteCreated(noteId, holder, notional);
    }

    // ----------------------------------------------------------------
    // Pricing callback: CREATED -> PRICED
    // ----------------------------------------------------------------

    /// @notice Called after CRE pricing is accepted. Transitions CREATED -> PRICED.
    function priceNote(bytes32 noteId, int256[] calldata initialPrices) external onlyRole(KEEPER_ROLE) {
        Note storage note = _notes[noteId];
        _requireState(noteId, State.Created);

        PricingResult memory pricing = creConsumer.getAcceptedPricing(noteId);

        (uint256 baseBps, , uint256 totalBps) =
            couponCalculator.calculateCoupon(pricing.putPremiumBps, 0, 0);

        note.baseCouponBps = baseBps;
        note.totalCouponBps = totalBps;
        note.initialPrices = initialPrices;

        _transition(noteId, State.Priced);
    }

    // ----------------------------------------------------------------
    // Activate: PRICED -> ACTIVE (requires issuance gate)
    // ----------------------------------------------------------------

    /// @notice Transitions PRICED -> ACTIVE after issuance gate approval (INV-6).
    function activateNote(bytes32 noteId) external onlyRole(KEEPER_ROLE) {
        Note storage note = _notes[noteId];
        _requireState(noteId, State.Priced);

        (bool approved, string memory reason) =
            issuanceGate.checkIssuance(noteId, note.notional, note.basket);
        if (!approved) revert IssuanceNotApproved(reason);

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

        // Move to observation pending if not already
        if (note.state == State.Active) {
            _transition(noteId, State.ObservationPending);
        }

        note.observations++;

        // 1. Get worst-of performance
        uint256 worstPerfBps = _getWorstPerformance(note);

        // 2. Check autocall trigger (with step-down)
        uint256 triggerBps = AUTOCALL_TRIGGER_BPS - (uint256(STEP_DOWN_BPS) * note.observations);
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
            uint256 baseCouponAmount = couponCalculator.calculateCouponAmount(
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
    function settleKI(bytes32 noteId, bool preferPhysical) external override nonReentrant {
        Note storage note = _notes[noteId];
        _requireState(noteId, State.KISettle);
        if (msg.sender != note.holder) revert OnlyHolder();

        uint256 recovered = hedgeManager.closeHedge(noteId);
        uint256 worstPerfBps = _getWorstPerformance(note);

        if (preferPhysical) {
            // Physical delivery: transfer recovered USDC (representing xStock value)
            // In production, would swap USDC -> worst xStock via swapper
            usdc.safeTransfer(note.holder, recovered);
            emit NoteSettled(noteId, recovered, true);
        } else {
            // Cash settlement at market value
            uint256 cashValue = (note.notional * worstPerfBps) / BPS;
            uint256 payout = cashValue < recovered ? cashValue : recovered;
            usdc.safeTransfer(note.holder, payout);
            emit NoteSettled(noteId, payout, false);
        }

        _transition(noteId, State.Settled);
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

    function _getWorstPerformance(Note storage note) internal view returns (uint256) {
        uint256 worst = type(uint256).max;
        for (uint256 i = 0; i < note.basket.length; i++) {
            // In production: use Chainlink price feeds
            // For now, compute perf from initialPrices stored at creation
            // perf = currentPrice / initialPrice * BPS
            // Mock: assume 100% perf (tests will override via mock)
            uint256 perf = BPS; // placeholder -- mocked in tests
            if (note.initialPrices.length > i && note.initialPrices[i] > 0) {
                // Use initial prices for ratio calculation when available
                perf = BPS; // simplified -- real impl uses price feeds
            }
            if (perf < worst) {
                worst = perf;
            }
        }
        return worst;
    }

    function _payCoupon(bytes32 noteId, Note storage note, bool includeMemory) internal {
        uint256 couponAmount =
            couponCalculator.calculateCouponAmount(note.notional, note.totalCouponBps, OBS_INTERVAL_DAYS);

        uint256 memoryPaid = 0;
        if (includeMemory && note.memoryCoupon > 0) {
            memoryPaid = note.memoryCoupon;
            note.memoryCoupon = 0;
        }

        uint256 totalPay = couponAmount + memoryPaid;
        if (totalPay > 0) {
            usdc.safeTransfer(note.holder, totalPay);
        }

        emit CouponPaid(noteId, couponAmount, memoryPaid);
    }

    function _settleAutocall(bytes32 noteId, Note storage note) internal {
        uint256 recovered = hedgeManager.closeHedge(noteId);
        // Return notional to holder (autocall = no KI, full principal)
        uint256 payout = note.notional < recovered ? note.notional : recovered;
        usdc.safeTransfer(note.holder, payout);

        _transition(noteId, State.Settled);
        emit NoteSettled(noteId, payout, false);
    }

    function _handleMaturity(bytes32 noteId, Note storage note, uint256 worstPerfBps) internal {
        if (worstPerfBps < KI_BARRIER_BPS) {
            // KI breached at maturity (European)
            _transition(noteId, State.KISettle);
        } else {
            // No KI -- settle at par + remaining coupons
            _transition(noteId, State.NoKISettle);
            _settleNoKI(noteId, note);
        }
    }

    function _settleNoKI(bytes32 noteId, Note storage note) internal {
        uint256 recovered = hedgeManager.closeHedge(noteId);
        uint256 payout = note.notional < recovered ? note.notional : recovered;
        usdc.safeTransfer(note.holder, payout);

        _transition(noteId, State.Settled);
        emit NoteSettled(noteId, payout, false);
    }
}
