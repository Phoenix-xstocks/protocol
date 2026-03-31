// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IHedgeManager } from "../interfaces/IHedgeManager.sol";
import { INadoAdapter } from "../interfaces/INadoAdapter.sol";
import { ITydroAdapter } from "../interfaces/ITydroAdapter.sol";
import { IOneInchSwapper } from "../interfaces/IOneInchSwapper.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title HedgeManager
/// @notice Orchestrates spot + perps + collateral for delta-neutral hedge.
///         Open/close/rebalance with delta drift monitoring and circuit breaker.
contract HedgeManager is IHedgeManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10000;
    uint256 public constant DELTA_THRESHOLD_BPS = 500; // 5% drift -> trigger rebalance
    uint256 public constant DELTA_CRITICAL_BPS = 1500; // 15% drift -> circuit breaker
    uint256 public constant MAX_REBALANCE_COST = 50; // 0.5% of notional max per rebalance
    uint256 public constant DEFAULT_LEVERAGE = 1; // 1x for delta-neutral

    INadoAdapter public nado;
    ITydroAdapter public tydro;
    IOneInchSwapper public swapper;
    IERC20 public usdc;

    /// @notice Authorized callers (AutocallEngine, EpochManager, etc.)
    mapping(address => bool) public authorized;

    modifier onlyAuthorized() {
        require(msg.sender == owner() || authorized[msg.sender], "not authorized");
        _;
    }

    function setAuthorized(address account, bool status) external onlyOwner {
        authorized[account] = status;
    }

    struct StockHedge {
        address asset;
        uint256 spotAmount; // xStock quantity held
        uint256 perpNotional; // USDC notional of short perp
        bytes32 positionId; // Nado position id
        uint256 pairIndex; // Nado pair index
    }

    struct HedgePosition {
        address[] basket;
        uint256 notional; // Total USDC notional
        uint256 spotNotional; // Total spot value at open
        uint256 tydroBorrowed; // USDC borrowed from Tydro
        uint256 openTimestamp;
        bool active;
        mapping(uint256 => StockHedge) stocks; // index -> StockHedge
        uint256 stockCount;
    }

    mapping(bytes32 => HedgePosition) internal positions;
    mapping(address => uint256) public pairIndexes; // xStock address -> Nado pair index
    /// @notice Per-note circuit breaker pausing
    mapping(bytes32 => bool) public notePaused;

    event HedgeOpened(bytes32 indexed noteId, uint256 notional, uint256 spotNotional, uint256 borrowed);
    event HedgeClosed(bytes32 indexed noteId, uint256 recovered, int256 pnl);
    event HedgeRebalanced(bytes32 indexed noteId, int256 deltaDrift);
    event EmergencyPaused(bytes32 indexed noteId, string reason);
    event PairIndexSet(address indexed asset, uint256 pairIndex);

    constructor(
        address _nado,
        address _tydro,
        address _swapper,
        address _usdc,
        address _owner
    ) Ownable(_owner) {
        require(_nado != address(0), "zero nado");
        require(_tydro != address(0), "zero tydro");
        require(_swapper != address(0), "zero swapper");
        require(_usdc != address(0), "zero usdc");
        nado = INadoAdapter(_nado);
        tydro = ITydroAdapter(_tydro);
        swapper = IOneInchSwapper(_swapper);
        usdc = IERC20(_usdc);
    }

    /// @notice Set pair index for a given xStock asset
    function setPairIndex(address asset, uint256 pairIndex) external onlyOwner {
        pairIndexes[asset] = pairIndex;
        emit PairIndexSet(asset, pairIndex);
    }

    /// @inheritdoc IHedgeManager
    function openHedge(
        bytes32 noteId,
        address[] calldata basket,
        uint256 notional
    ) external onlyAuthorized nonReentrant {
        require(!notePaused[noteId], "note paused");
        require(!positions[noteId].active, "hedge already active");
        require(basket.length > 0, "empty basket");
        require(notional > 0, "zero notional");

        HedgePosition storage pos = positions[noteId];
        pos.notional = notional;
        pos.openTimestamp = block.timestamp;
        pos.active = true;
        pos.stockCount = basket.length;
        pos.basket = basket;

        // Pull USDC from caller (AutocallEngine) to fund the hedge
        usdc.safeTransferFrom(msg.sender, address(this), notional);

        uint256 perStock = notional / basket.length;
        uint256 totalSpot;

        for (uint256 i = 0; i < basket.length; i++) {
            // 1. Buy xStocks spot via 1inch
            usdc.safeIncreaseAllowance(address(swapper), perStock);
            uint256 xStockAmount = swapper.swap(address(usdc), basket[i], perStock);

            // 2. Deposit xStocks on Tydro as collateral
            IERC20(basket[i]).safeIncreaseAllowance(address(tydro), xStockAmount);
            tydro.depositCollateral(basket[i], xStockAmount);

            // 3. Short stock perps on Nado (delta hedge)
            uint256 pairIdx = pairIndexes[basket[i]];
            bytes32 positionId = nado.openShort(pairIdx, perStock, DEFAULT_LEVERAGE);

            pos.stocks[i] = StockHedge({
                asset: basket[i],
                spotAmount: xStockAmount,
                perpNotional: perStock,
                positionId: positionId,
                pairIndex: pairIdx
            });

            totalSpot += perStock;
        }

        // 4. Borrow USDC from Tydro (margin for perps)
        uint256 borrowed = tydro.borrowUSDC(notional / 2);
        pos.tydroBorrowed = borrowed;
        pos.spotNotional = totalSpot;

        emit HedgeOpened(noteId, notional, totalSpot, borrowed);
    }

    /// @inheritdoc IHedgeManager
    function closeHedge(bytes32 noteId) external onlyAuthorized nonReentrant returns (uint256 recovered) {
        HedgePosition storage pos = positions[noteId];
        require(pos.active, "hedge not active");

        // 1. Close all short perps on Nado
        for (uint256 i = 0; i < pos.stockCount; i++) {
            StockHedge storage sh = pos.stocks[i];
            nado.closeShort(sh.positionId);
        }

        // 2. Repay Tydro borrow
        if (pos.tydroBorrowed > 0) {
            usdc.safeIncreaseAllowance(address(tydro), pos.tydroBorrowed);
            tydro.repayUSDC(pos.tydroBorrowed);
        }

        // 3. Withdraw xStocks from Tydro and sell via 1inch
        for (uint256 i = 0; i < pos.stockCount; i++) {
            StockHedge storage sh = pos.stocks[i];
            uint256 xStockAmount = tydro.withdrawCollateral(sh.asset);
            IERC20(sh.asset).safeIncreaseAllowance(address(swapper), xStockAmount);
            recovered += swapper.swap(sh.asset, address(usdc), xStockAmount);
        }

        int256 pnl = int256(recovered) - int256(pos.spotNotional);
        pos.active = false;

        // Transfer recovered USDC back to caller (AutocallEngine)
        if (recovered > 0) {
            usdc.safeTransfer(msg.sender, recovered);
        }

        emit HedgeClosed(noteId, recovered, pnl);
    }

    /// @inheritdoc IHedgeManager
    function rebalance(bytes32 noteId) external nonReentrant {
        require(!notePaused[noteId], "note paused");
        HedgePosition storage pos = positions[noteId];
        require(pos.active, "hedge not active");

        int256 drift = _calculateDeltaDrift(noteId);
        uint256 absDrift = _abs(drift);

        if (absDrift > DELTA_THRESHOLD_BPS) {
            // Attempt adjustment first
            _adjustPerps(noteId, drift);
            emit HedgeRebalanced(noteId, drift);

            // Check if drift is still critical after adjustment
            int256 postDrift = _calculateDeltaDrift(noteId);
            uint256 absPostDrift = _abs(postDrift);
            if (absPostDrift > DELTA_CRITICAL_BPS) {
                notePaused[noteId] = true;
                emit EmergencyPaused(noteId, "delta drift critical after rebalance");
            }
        }
    }

    /// @inheritdoc IHedgeManager
    function getDeltaDrift(bytes32 noteId) external view returns (int256 driftBps) {
        return _calculateDeltaDrift(noteId);
    }

    /// @notice Get position details
    function getPosition(bytes32 noteId)
        external
        view
        returns (uint256 notional, uint256 spotNotional, uint256 borrowed, bool active)
    {
        HedgePosition storage pos = positions[noteId];
        return (pos.notional, pos.spotNotional, pos.tydroBorrowed, pos.active);
    }

    /// @notice Unpause a specific note after emergency (owner only, e.g. multisig)
    function unpauseNote(bytes32 noteId) external onlyOwner {
        notePaused[noteId] = false;
    }

    // --- Internal ---

    function _calculateDeltaDrift(bytes32 noteId) internal view returns (int256) {
        HedgePosition storage pos = positions[noteId];
        if (!pos.active || pos.notional == 0) return 0;

        uint256 spotValue;
        uint256 perpValue;

        for (uint256 i = 0; i < pos.stockCount; i++) {
            StockHedge storage sh = pos.stocks[i];
            spotValue += tydro.getCollateralValue(sh.asset);
            (, , uint256 size, ) = nado.getPosition(sh.positionId);
            perpValue += size;
        }

        if (spotValue >= perpValue) {
            return int256((spotValue - perpValue) * BPS / pos.notional);
        } else {
            return -int256((perpValue - spotValue) * BPS / pos.notional);
        }
    }

    /// @notice Adjust perp positions to match current spot values.
    ///         Only adjusts positions where drift exceeds per-stock threshold.
    function _adjustPerps(bytes32 noteId, int256) internal {
        HedgePosition storage pos = positions[noteId];

        for (uint256 i = 0; i < pos.stockCount; i++) {
            StockHedge storage sh = pos.stocks[i];
            uint256 spotVal = tydro.getCollateralValue(sh.asset);

            // Only rebalance if per-stock drift is significant (>2%)
            uint256 diff = spotVal > sh.perpNotional
                ? spotVal - sh.perpNotional
                : sh.perpNotional - spotVal;
            if (diff * BPS / (sh.perpNotional > 0 ? sh.perpNotional : 1) > 200) {
                nado.closeShort(sh.positionId);
                bytes32 newPosId = nado.openShort(sh.pairIndex, spotVal, DEFAULT_LEVERAGE);
                sh.positionId = newPosId;
                sh.perpNotional = spotVal;
            }
        }
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
}
