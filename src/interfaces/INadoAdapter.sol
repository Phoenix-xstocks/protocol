// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface INadoAdapter {
    function openShort(
        uint256 pairIndex,
        uint256 notional,
        uint256 leverage
    ) external returns (bytes32 positionId);

    function closeShort(bytes32 positionId) external returns (uint256 pnl);

    function claimFunding(bytes32 positionId) external returns (uint256 fundingAmount);

    function getPosition(bytes32 positionId)
        external
        view
        returns (int256 unrealizedPnl, uint256 margin, uint256 size, uint256 accumulatedFunding);
}
