// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ICarryEngine } from "../interfaces/ICarryEngine.sol";
import { INadoAdapter } from "../interfaces/INadoAdapter.sol";
import { ITydroAdapter } from "../interfaces/ITydroAdapter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CarryEngine
/// @notice Multi-source carry aggregator:
///         A: Funding rate from Nado short perps (~55% of carry)
///         B: USDC lending on Tydro (~35%)
///         C: xStocks collateral yield on Tydro (~10%)
contract CarryEngine is ICarryEngine, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    INadoAdapter public nado;
    ITydroAdapter public tydro;
    IERC20 public usdc;

    /// @notice Cached rates (updated each epoch)
    uint256 public lastFundingRateBps;
    uint256 public lastLendingRateBps;
    uint256 public lastCollateralYieldBps;
    uint256 public lastUpdateTimestamp;

    /// @notice Tracks collected carry per note
    mapping(bytes32 => uint256) public totalCarryCollected;

    /// @notice Tracks Nado position IDs per note for funding collection
    struct NotePositions {
        bytes32[] positionIds;
        uint256 usdcLent;
    }

    mapping(bytes32 => NotePositions) internal notePositions;

    event CarryCollected(
        bytes32 indexed noteId, uint256 fundingCarry, uint256 lendingCarry, uint256 collateralYield
    );
    event RatesUpdated(uint256 fundingRateBps, uint256 lendingRateBps, uint256 collateralYieldBps);
    event PositionsRegistered(bytes32 indexed noteId, uint256 positionCount, uint256 usdcLent);

    constructor(address _nado, address _tydro, address _usdc, address _owner) Ownable(_owner) {
        require(_nado != address(0), "zero nado");
        require(_tydro != address(0), "zero tydro");
        require(_usdc != address(0), "zero usdc");
        nado = INadoAdapter(_nado);
        tydro = ITydroAdapter(_tydro);
        usdc = IERC20(_usdc);
    }

    /// @notice Register Nado positions and USDC lending for a note
    function registerPositions(
        bytes32 noteId,
        bytes32[] calldata positionIds,
        uint256 usdcLent
    ) external onlyOwner {
        NotePositions storage np = notePositions[noteId];
        for (uint256 i = 0; i < positionIds.length; i++) {
            np.positionIds.push(positionIds[i]);
        }
        np.usdcLent = usdcLent;
        emit PositionsRegistered(noteId, positionIds.length, usdcLent);
    }

    /// @inheritdoc ICarryEngine
    function collectCarry(bytes32 noteId)
        external
        onlyOwner
        returns (uint256 fundingCarry, uint256 lendingCarry)
    {
        NotePositions storage np = notePositions[noteId];

        // Source A: Funding rate from Nado short perps
        for (uint256 i = 0; i < np.positionIds.length; i++) {
            fundingCarry += nado.claimFunding(np.positionIds[i]);
        }

        // Source B: USDC lending on Tydro (pro-rata based on lending rate)
        uint256 lendingRatePerSec = tydro.getLendingRate();
        uint256 elapsed = block.timestamp - (lastUpdateTimestamp > 0 ? lastUpdateTimestamp : block.timestamp);
        if (np.usdcLent > 0 && elapsed > 0) {
            lendingCarry = (np.usdcLent * lendingRatePerSec * elapsed) / 1e18;
        }

        // Source C: Collateral yield (included in lending carry for simplicity)

        totalCarryCollected[noteId] += fundingCarry + lendingCarry;

        emit CarryCollected(noteId, fundingCarry, lendingCarry, 0);
    }

    /// @inheritdoc ICarryEngine
    function getTotalCarryRate() external view returns (uint256 rateBps) {
        return lastFundingRateBps + lastLendingRateBps + lastCollateralYieldBps;
    }

    /// @inheritdoc ICarryEngine
    function getFundingRate() external view returns (uint256 rateBps) {
        return lastFundingRateBps;
    }

    /// @inheritdoc ICarryEngine
    function getLendingRate() external view returns (uint256 rateBps) {
        return lastLendingRateBps;
    }

    /// @notice Update cached rates (called each epoch)
    function updateRates(
        uint256 fundingRateBps,
        uint256 lendingRateBps,
        uint256 collateralYieldBps
    ) external onlyOwner {
        lastFundingRateBps = fundingRateBps;
        lastLendingRateBps = lendingRateBps;
        lastCollateralYieldBps = collateralYieldBps;
        lastUpdateTimestamp = block.timestamp;
        emit RatesUpdated(fundingRateBps, lendingRateBps, collateralYieldBps);
    }
}
