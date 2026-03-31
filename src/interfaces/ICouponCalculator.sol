// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICouponCalculator {
    function calculateCoupon(
        uint256 optionPremiumBps,
        uint256 avgVolBps,
        uint256 carryRateBps
    ) external view returns (uint256 baseCouponBps, uint256 carryEnhanceBps, uint256 totalCouponBps);

    function calculateCouponAmount(
        uint256 notional,
        uint256 totalCouponBps,
        uint256 obsIntervalDays
    ) external pure returns (uint256 couponAmount);
}
