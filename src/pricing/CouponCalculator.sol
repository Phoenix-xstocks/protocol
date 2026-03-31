// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ICouponCalculator } from "../interfaces/ICouponCalculator.sol";

/// @title CouponCalculator
/// @notice Computes coupon rates for Phoenix Autocall notes.
///         base = premium - safety_margin (dynamic, vol-linked)
///         carry_enhance = min(carry_rate * share / BPS, MAX_CARRY_ENHANCE)
///         total = base + enhance
contract CouponCalculator is ICouponCalculator {
    uint256 public constant BPS = 10000;

    uint256 public constant SAFETY_MARGIN_HIGH_VOL = 200;
    uint256 public constant SAFETY_MARGIN_MID_VOL = 150;
    uint256 public constant SAFETY_MARGIN_LOW_VOL = 100;

    uint256 public constant CARRY_SHARE_RATE = 7000;
    uint256 public constant MAX_CARRY_ENHANCE = 500;

    function calculateCoupon(
        uint256 optionPremiumBps,
        uint256 avgVolBps,
        uint256 carryRateBps
    ) external pure returns (uint256 baseCouponBps, uint256 carryEnhanceBps, uint256 totalCouponBps) {
        uint256 safetyMargin = _getSafetyMargin(avgVolBps);
        require(optionPremiumBps > safetyMargin, "premium <= safety margin");

        baseCouponBps = optionPremiumBps - safetyMargin;

        uint256 rawCarryEnhance = (carryRateBps * CARRY_SHARE_RATE) / BPS;
        carryEnhanceBps = rawCarryEnhance < MAX_CARRY_ENHANCE ? rawCarryEnhance : MAX_CARRY_ENHANCE;

        totalCouponBps = baseCouponBps + carryEnhanceBps;
    }

    function calculateCouponAmount(
        uint256 notional,
        uint256 totalCouponBps,
        uint256 obsIntervalDays
    ) external pure returns (uint256 couponAmount) {
        couponAmount = (notional * totalCouponBps * obsIntervalDays) / (365 * BPS);
    }

    function getSafetyMargin(uint256 avgVolBps) external pure returns (uint256) {
        return _getSafetyMargin(avgVolBps);
    }

    function _getSafetyMargin(uint256 avgVolBps) internal pure returns (uint256) {
        if (avgVolBps >= 5000) return SAFETY_MARGIN_HIGH_VOL;
        if (avgVolBps >= 3500) return SAFETY_MARGIN_MID_VOL;
        return SAFETY_MARGIN_LOW_VOL;
    }
}
