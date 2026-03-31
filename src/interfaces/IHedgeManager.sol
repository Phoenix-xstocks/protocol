// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IHedgeManager {
    function openHedge(
        bytes32 noteId,
        address[] calldata basket,
        uint256 notional
    ) external;

    function closeHedge(bytes32 noteId) external returns (uint256 recovered);

    function rebalance(bytes32 noteId) external;

    function getDeltaDrift(bytes32 noteId) external view returns (int256 driftBps);
}
