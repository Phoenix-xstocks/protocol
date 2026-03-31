// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct PricingResult {
    uint16 putPremiumBps;
    uint16 kiProbabilityBps;
    uint16 expectedKILossBps;
    uint16 vegaBps;
    bytes32 inputsHash;
}

interface ICREConsumer {
    function fulfillPricing(bytes32 noteId, PricingResult calldata result) external;

    function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory);
}
