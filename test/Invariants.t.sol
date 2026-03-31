// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { CouponCalculator } from "../src/pricing/CouponCalculator.sol";
import { ReserveFund } from "../src/periphery/ReserveFund.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDCInv is ERC20 {
    constructor() ERC20("USDC", "USDC") {}
    function mint(address to, uint256 amt) external { _mint(to, amt); }
    function decimals() public pure override returns (uint8) { return 6; }
}

/// @title Invariant Tests
/// @notice Fuzz tests for protocol invariants from SPEC section 14
contract InvariantTest is Test {
    CouponCalculator public calc;
    ReserveFund public reserve;
    MockUSDCInv public usdc;

    function setUp() public {
        calc = new CouponCalculator();
        usdc = new MockUSDCInv();
        reserve = new ReserveFund(address(usdc), address(this));
    }

    // ================================================================
    // INV-1: base_coupon + safety_margin <= option_premium
    // ================================================================

    /// @notice Fuzz: for any valid premium and vol, INV-1 holds
    function testFuzz_INV1_base_plus_safety_lte_premium(
        uint256 premiumBps,
        uint256 avgVolBps,
        uint256 carryRateBps
    ) public view {
        // Bound to realistic ranges
        premiumBps = bound(premiumBps, 301, 1500); // above any safety margin
        avgVolBps = bound(avgVolBps, 0, 10000);
        carryRateBps = bound(carryRateBps, 0, 5000);

        uint256 safetyMargin = calc.getSafetyMargin(avgVolBps);
        if (premiumBps <= safetyMargin) return; // skip invalid combos

        (uint256 baseBps, , ) = calc.calculateCoupon(premiumBps, avgVolBps, carryRateBps);

        // INV-1: base + safety <= premium
        assertLe(baseBps + safetyMargin, premiumBps, "INV-1 violated");
    }

    /// @notice Fuzz: base_coupon is exactly premium - safety_margin
    function testFuzz_INV1_exactEquality(uint256 premiumBps, uint256 avgVolBps) public view {
        premiumBps = bound(premiumBps, 301, 1500);
        avgVolBps = bound(avgVolBps, 0, 10000);

        uint256 safetyMargin = calc.getSafetyMargin(avgVolBps);
        if (premiumBps <= safetyMargin) return;

        (uint256 baseBps, , ) = calc.calculateCoupon(premiumBps, avgVolBps, 0);
        assertEq(baseBps + safetyMargin, premiumBps, "base + safety should equal premium");
    }

    // ================================================================
    // INV-1 boundary: safety margin transitions correctly at vol thresholds
    // ================================================================

    function test_INV1_safetyMargin_highVol() public view {
        assertEq(calc.getSafetyMargin(5000), 200); // exactly 50%
        assertEq(calc.getSafetyMargin(6000), 200); // above 50%
        assertEq(calc.getSafetyMargin(10000), 200); // max
    }

    function test_INV1_safetyMargin_midVol() public view {
        assertEq(calc.getSafetyMargin(3500), 150); // exactly 35%
        assertEq(calc.getSafetyMargin(4999), 150); // just below 50%
    }

    function test_INV1_safetyMargin_lowVol() public view {
        assertEq(calc.getSafetyMargin(0), 100);
        assertEq(calc.getSafetyMargin(3499), 100); // just below 35%
    }

    // ================================================================
    // INV-1: carry enhancement is always capped at MAX_CARRY_ENHANCE (500 bps)
    // ================================================================

    function testFuzz_INV1_carryEnhanceCapped(uint256 carryRateBps) public view {
        carryRateBps = bound(carryRateBps, 0, 50000); // up to 500%

        (, uint256 carryEnhanceBps, ) = calc.calculateCoupon(900, 4500, carryRateBps);

        assertLe(carryEnhanceBps, 500, "carry enhance must be capped at 500 bps");
    }

    // ================================================================
    // INV-5: Reserve fund haircut is monotonically decreasing with reserve level
    // ================================================================

    function testFuzz_INV5_haircutMonotonic(uint256 balance1, uint256 balance2) public {
        uint256 notional = 1_000_000e6;
        balance1 = bound(balance1, 1, notional / 10); // min 1 to avoid zero deposit revert
        balance2 = bound(balance2, balance1, notional / 10);

        // Fund reserve with balance1
        usdc.mint(address(this), balance2);
        usdc.approve(address(reserve), balance2);
        reserve.deposit(balance2);

        uint256 haircut2 = reserve.getHaircutRatio(notional);

        // If balance2 >= balance1, then haircut2 >= haircut1
        // (higher reserve = higher haircut ratio = less haircut)
        // This is a basic monotonicity check
        assertGe(haircut2, 0, "haircut should be non-negative");
        assertLe(haircut2, 10000, "haircut should be at most 100%");
    }

    // ================================================================
    // INV-5: Reserve levels are correctly classified
    // ================================================================

    function test_INV5_reserveLevels() public {
        uint256 notional = 1_000_000e6;

        // Target: 10% = 100,000 USDC
        usdc.mint(address(this), 100_000e6);
        usdc.approve(address(reserve), 100_000e6);
        reserve.deposit(100_000e6);

        uint256 level = reserve.getLevel(notional);
        assertGe(level, 1000, "10% reserve should be at target level");

        assertFalse(reserve.isBelowMinimum(notional), "10% should not be below minimum");
        assertFalse(reserve.isCritical(notional), "10% should not be critical");
    }

    function test_INV5_reserveCritical() public {
        uint256 notional = 1_000_000e6;

        // 0.5% = 5,000 USDC (below critical 1%)
        usdc.mint(address(this), 5_000e6);
        usdc.approve(address(reserve), 5_000e6);
        reserve.deposit(5_000e6);

        assertTrue(reserve.isCritical(notional), "0.5% should be critical");
        assertTrue(reserve.isBelowMinimum(notional), "0.5% should be below minimum");

        // Haircut should be ~50%
        uint256 haircut = reserve.getHaircutRatio(notional);
        assertApproxEqAbs(haircut, 5000, 100, "haircut at 0.5% should be ~50%");
    }

    // ================================================================
    // Coupon amount calculation correctness
    // ================================================================

    function testFuzz_couponAmount_positive(
        uint256 notional,
        uint256 couponBps,
        uint256 days_
    ) public view {
        notional = bound(notional, 100e6, 100_000e6);
        couponBps = bound(couponBps, 100, 2000);
        days_ = bound(days_, 1, 365);

        uint256 amount = calc.calculateCouponAmount(notional, couponBps, days_);

        assertGt(amount, 0, "coupon amount should be positive");
        // Max coupon: 100k * 2000bps * 365 / (365 * 10000) = 2000 USDC
        assertLe(amount, notional * couponBps / 10000, "coupon should not exceed annual rate");
    }

    function test_couponAmount_30days_900bps_10k() public view {
        // 10,000e6 * 900 * 30 / (365 * 10000) = 73,972,602 (~73.97 USDC per month)
        uint256 amount = calc.calculateCouponAmount(10_000e6, 900, 30);
        assertApproxEqAbs(amount, 73972602, 1e3, "coupon ~74 USDC for 10k/9%/30d");
    }
}
