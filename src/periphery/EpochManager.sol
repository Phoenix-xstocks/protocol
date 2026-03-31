// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IEpochManager } from "../interfaces/IEpochManager.sol";
import { IReserveFund } from "../interfaces/IReserveFund.sol";
import { IFeeCollector } from "../interfaces/IFeeCollector.sol";
import { ICarryEngine } from "../interfaces/ICarryEngine.sol";
import { IHedgeManager } from "../interfaces/IHedgeManager.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title EpochManager
/// @notice 48h epoch cycles. NAV calculation, waterfall distribution (P1-P6),
///         rebalance trigger.
///
/// Waterfall priority (strict order, NEVER skip):
///   P1 (SENIOR): Base coupons due -- ALWAYS paid first
///   P2 (SENIOR): Principal repayment
///   P3 (MEZZ):   Carry enhancement retail
///   P4 (JUNIOR): Hedge operational costs
///   P5 (JUNIOR): Reserve fund contribution
///   P6 (EQUITY): Protocol treasury
///   NEVER P6 if P1 unpaid
contract EpochManager is IEpochManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10000;
    uint256 public constant EPOCH_DURATION = 48 hours;
    uint256 public constant RESERVE_CONTRIBUTION_BPS = 3000; // 30% of carry net

    IERC20 public usdc;
    IReserveFund public reserveFund;
    IFeeCollector public feeCollector;
    ICarryEngine public carryEngine;
    IHedgeManager public hedgeManager;

    uint256 public currentEpoch;
    uint256 public epochStartTimestamp;
    uint256 public totalNotionalOutstanding;

    /// @notice Amounts due for waterfall distribution
    struct WaterfallAmounts {
        uint256 baseCouponsDue; // P1
        uint256 principalDue; // P2
        uint256 carryEnhancementDue; // P3
        uint256 hedgeCostsDue; // P4
    }

    /// @notice Result of waterfall distribution
    struct WaterfallResult {
        uint256 p1Paid;
        uint256 p2Paid;
        uint256 p3Paid;
        uint256 p4Paid;
        uint256 p5Paid;
        uint256 p6Paid;
        bool p1FullyPaid;
    }

    /// @notice Active note IDs for rebalancing
    bytes32[] public activeNoteIds;

    /// @notice Configurable waterfall amounts (set by owner before distribution)
    WaterfallAmounts public pendingAmounts;

    /// @notice Last distribution result
    WaterfallResult public lastResult;

    event EpochAdvanced(uint256 indexed epochId, uint256 timestamp);
    event WaterfallDistributed(
        uint256 indexed epochId,
        uint256 p1Paid,
        uint256 p2Paid,
        uint256 p3Paid,
        uint256 p4Paid,
        uint256 p5Paid,
        uint256 p6Paid
    );
    event RebalanceTriggered(uint256 indexed epochId, bytes32 noteId);
    event NoteAdded(bytes32 indexed noteId);
    event NoteRemoved(bytes32 indexed noteId);

    constructor(
        address _usdc,
        address _reserveFund,
        address _feeCollector,
        address _carryEngine,
        address _hedgeManager,
        address _owner
    ) Ownable(_owner) {
        require(_usdc != address(0), "zero usdc");
        require(_reserveFund != address(0), "zero reserveFund");
        require(_feeCollector != address(0), "zero feeCollector");
        require(_carryEngine != address(0), "zero carryEngine");
        require(_hedgeManager != address(0), "zero hedgeManager");

        usdc = IERC20(_usdc);
        reserveFund = IReserveFund(_reserveFund);
        feeCollector = IFeeCollector(_feeCollector);
        carryEngine = ICarryEngine(_carryEngine);
        hedgeManager = IHedgeManager(_hedgeManager);

        epochStartTimestamp = block.timestamp;
    }

    /// @notice Register an active note for epoch processing
    function addNote(bytes32 noteId, uint256 notional) external onlyOwner {
        activeNoteIds.push(noteId);
        totalNotionalOutstanding += notional;
        emit NoteAdded(noteId);
    }

    /// @notice Remove a settled note
    function removeNote(uint256 index, uint256 notional) external onlyOwner {
        require(index < activeNoteIds.length, "invalid index");
        bytes32 noteId = activeNoteIds[index];
        // Swap with last and pop
        activeNoteIds[index] = activeNoteIds[activeNoteIds.length - 1];
        activeNoteIds.pop();
        totalNotionalOutstanding -= notional;
        emit NoteRemoved(noteId);
    }

    /// @notice Set waterfall amounts for next distribution
    function setPendingAmounts(
        uint256 baseCouponsDue,
        uint256 principalDue,
        uint256 carryEnhancementDue,
        uint256 hedgeCostsDue
    ) external onlyOwner {
        pendingAmounts = WaterfallAmounts({
            baseCouponsDue: baseCouponsDue,
            principalDue: principalDue,
            carryEnhancementDue: carryEnhancementDue,
            hedgeCostsDue: hedgeCostsDue
        });
    }

    /// @inheritdoc IEpochManager
    function getCurrentEpoch() external view returns (uint256) {
        return currentEpoch;
    }

    /// @inheritdoc IEpochManager
    function getEpochStart(uint256 epochId) external view returns (uint256 timestamp) {
        return epochStartTimestamp + (epochId * EPOCH_DURATION);
    }

    /// @inheritdoc IEpochManager
    function isEpochReady() public view returns (bool) {
        return block.timestamp >= epochStartTimestamp + ((currentEpoch + 1) * EPOCH_DURATION);
    }

    /// @inheritdoc IEpochManager
    function advanceEpoch() external onlyOwner {
        require(isEpochReady(), "epoch not ready");
        currentEpoch++;
        emit EpochAdvanced(currentEpoch, block.timestamp);
    }

    /// @inheritdoc IEpochManager
    /// @notice Distributes available cash according to P1-P6 waterfall.
    ///         Cash source: USDC balance of this contract.
    ///         INVARIANT: P6 is NEVER paid if P1 is not fully covered.
    function distributeWaterfall() external onlyOwner nonReentrant {
        uint256 available = usdc.balanceOf(address(this));
        WaterfallAmounts memory amounts = pendingAmounts;
        WaterfallResult memory result;

        // P1 (SENIOR): Base coupons due -- ALWAYS paid first
        if (available > 0 && amounts.baseCouponsDue > 0) {
            result.p1Paid = _min(available, amounts.baseCouponsDue);
            available -= result.p1Paid;
        }

        // If P1 not fully covered, try reserve fund backup
        if (result.p1Paid < amounts.baseCouponsDue) {
            uint256 deficit = amounts.baseCouponsDue - result.p1Paid;
            uint256 covered = reserveFund.coverDeficit(deficit);
            result.p1Paid += covered;
        }

        result.p1FullyPaid = (amounts.baseCouponsDue == 0) || (result.p1Paid >= amounts.baseCouponsDue);

        // P2 (SENIOR): Principal repayment
        if (available > 0 && amounts.principalDue > 0) {
            result.p2Paid = _min(available, amounts.principalDue);
            available -= result.p2Paid;
        }

        // P3 (MEZZ): Carry enhancement retail
        if (available > 0 && amounts.carryEnhancementDue > 0) {
            uint256 carryDue = amounts.carryEnhancementDue;

            // Apply haircut if reserve is critical
            uint256 haircutRatio = reserveFund.getHaircutRatio(totalNotionalOutstanding);
            if (haircutRatio < BPS) {
                carryDue = (carryDue * haircutRatio) / BPS;
            }

            result.p3Paid = _min(available, carryDue);
            available -= result.p3Paid;
        }

        // P4 (JUNIOR): Hedge operational costs
        if (available > 0 && amounts.hedgeCostsDue > 0) {
            result.p4Paid = _min(available, amounts.hedgeCostsDue);
            available -= result.p4Paid;
        }

        // P5 (JUNIOR): Reserve fund contribution (30% of remaining)
        if (available > 0) {
            uint256 reserveContrib = (available * RESERVE_CONTRIBUTION_BPS) / BPS;
            if (reserveContrib > 0) {
                usdc.safeIncreaseAllowance(address(reserveFund), reserveContrib);
                reserveFund.deposit(reserveContrib);
                result.p5Paid = reserveContrib;
                available -= reserveContrib;
            }
        }

        // P6 (EQUITY): Protocol treasury -- NEVER if P1 unpaid
        if (available > 0 && result.p1FullyPaid) {
            result.p6Paid = available;
        }

        lastResult = result;

        // Reset pending amounts
        delete pendingAmounts;

        emit WaterfallDistributed(
            currentEpoch, result.p1Paid, result.p2Paid, result.p3Paid, result.p4Paid, result.p5Paid, result.p6Paid
        );
    }

    /// @notice Trigger rebalance for all active notes
    function triggerRebalances() external {
        for (uint256 i = 0; i < activeNoteIds.length; i++) {
            bytes32 noteId = activeNoteIds[i];
            int256 drift = hedgeManager.getDeltaDrift(noteId);
            if (_abs(drift) > 500) {
                hedgeManager.rebalance(noteId);
                emit RebalanceTriggered(currentEpoch, noteId);
            }
        }
    }

    /// @notice Get last waterfall distribution result
    function getLastResult() external view returns (WaterfallResult memory) {
        return lastResult;
    }

    /// @notice Get count of active notes
    function getActiveNoteCount() external view returns (uint256) {
        return activeNoteIds.length;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
}
