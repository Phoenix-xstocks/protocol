// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct PricingParams {
    address[] basket;
    uint256 kiBarrierBps;
    uint256 couponBarrierBps;
    uint256 autocallTriggerBps;
    uint256 stepDownBps;
    uint256 maturityDays;
    uint256 numObservations;
}

interface IOptionPricer {
    function verifyPricing(
        PricingParams calldata params,
        uint256 mcPremiumBps,
        bytes32 mcHash
    ) external view returns (bool approved, uint256 onChainApprox);
}
