// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { PricingParams } from "./IOptionPricer.sol";

struct PricingResult {
    uint16 putPremiumBps;
    uint16 kiProbabilityBps;
    uint16 expectedKILossBps;
    uint16 vegaBps;
    bytes32 inputsHash;
}

interface ICREConsumer {
    function registerNoteParams(bytes32 noteId, PricingParams calldata params) external;

    function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory);
}
