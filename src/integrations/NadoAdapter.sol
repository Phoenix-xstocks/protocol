// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INadoAdapter} from "../interfaces/INadoAdapter.sol";

/// @notice Minimal interface for Nado perp DEX on Ink.
interface INadoPerp {
    function openPosition(
        uint256 pairIndex,
        bool isShort,
        uint256 notional,
        uint256 leverage,
        address margin
    ) external returns (bytes32 positionId);

    function closePosition(bytes32 positionId) external returns (int256 pnl);

    function claimFunding(bytes32 positionId) external returns (uint256 fundingAmount);

    function getPosition(bytes32 positionId)
        external
        view
        returns (int256 unrealizedPnl, uint256 margin, uint256 size, uint256 accumulatedFunding);
}

/// @title NadoAdapter
/// @notice Adapter for Nado stock perps on Ink. Opens/closes shorts and claims funding.
contract NadoAdapter is INadoAdapter, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    INadoPerp public immutable nadoPerp;
    IERC20 public immutable marginToken;

    struct Position {
        uint256 pairIndex;
        uint256 notional;
        uint256 leverage;
        bool open;
    }

    mapping(bytes32 => Position) public positions;

    event ShortOpened(bytes32 indexed positionId, uint256 pairIndex, uint256 notional, uint256 leverage);
    event ShortClosed(bytes32 indexed positionId, uint256 pnl);
    event FundingClaimed(bytes32 indexed positionId, uint256 fundingAmount);

    error PositionNotOpen(bytes32 positionId);
    error PositionAlreadyExists(bytes32 positionId);

    constructor(address _nadoPerp, address _marginToken, address _owner) Ownable(_owner) {
        nadoPerp = INadoPerp(_nadoPerp);
        marginToken = IERC20(_marginToken);
    }

    /// @inheritdoc INadoAdapter
    function openShort(
        uint256 pairIndex,
        uint256 notional,
        uint256 leverage
    ) external onlyOwner nonReentrant returns (bytes32 positionId) {
        uint256 marginRequired = notional / leverage;
        marginToken.forceApprove(address(nadoPerp), marginRequired);

        positionId = nadoPerp.openPosition(pairIndex, true, notional, leverage, address(marginToken));

        if (positions[positionId].open) revert PositionAlreadyExists(positionId);

        positions[positionId] = Position({
            pairIndex: pairIndex,
            notional: notional,
            leverage: leverage,
            open: true
        });

        emit ShortOpened(positionId, pairIndex, notional, leverage);
    }

    /// @inheritdoc INadoAdapter
    function closeShort(bytes32 positionId) external onlyOwner nonReentrant returns (uint256 pnl) {
        if (!positions[positionId].open) revert PositionNotOpen(positionId);

        int256 rawPnl = nadoPerp.closePosition(positionId);
        positions[positionId].open = false;

        // Return absolute PnL; negative PnL returns 0 to caller (loss handled by margin)
        // forge-lint: disable-next-line(unsafe-typecast)
        pnl = rawPnl > 0 ? uint256(rawPnl) : 0;

        emit ShortClosed(positionId, pnl);
    }

    /// @inheritdoc INadoAdapter
    function claimFunding(bytes32 positionId) external onlyOwner nonReentrant returns (uint256 fundingAmount) {
        if (!positions[positionId].open) revert PositionNotOpen(positionId);

        fundingAmount = nadoPerp.claimFunding(positionId);

        emit FundingClaimed(positionId, fundingAmount);
    }

    /// @inheritdoc INadoAdapter
    function getPosition(bytes32 positionId)
        external
        view
        returns (int256 unrealizedPnl, uint256 margin, uint256 size, uint256 accumulatedFunding)
    {
        return nadoPerp.getPosition(positionId);
    }

    /// @notice Recover tokens sent to this contract by mistake.
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
