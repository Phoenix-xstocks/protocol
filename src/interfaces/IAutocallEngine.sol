// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

enum State {
    Created,
    Priced,
    Active,
    ObservationPending,
    Autocalled,
    MaturityCheck,
    NoKISettle,
    KISettle,
    Settled,
    Rolled,
    EmergencyPaused,
    Cancelled
}

interface IAutocallEngine {
    function createNote(
        address[] calldata basket,
        uint256 notional,
        address holder
    ) external returns (bytes32 noteId);

    function observe(bytes32 noteId) external;

    function settleKi(bytes32 noteId, bool preferPhysical) external;

    function getState(bytes32 noteId) external view returns (State);

    function getNoteCount() external view returns (uint256);
}
