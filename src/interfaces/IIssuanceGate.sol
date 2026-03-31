// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IIssuanceGate {
    function checkIssuance(
        bytes32 noteId,
        uint256 notional,
        address[] calldata basket
    ) external view returns (bool approved, string memory reason);
}
