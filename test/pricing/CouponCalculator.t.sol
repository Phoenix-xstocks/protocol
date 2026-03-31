// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { CouponCalculator } from "../../src/pricing/CouponCalculator.sol";

contract CouponCalculatorTest is Test {
    CouponCalculator public calc;

    function setUp() public {
        calc = new CouponCalculator();
    }

    function test_INV1_highVol() public view {
        uint256 premium = 920;
        (uint256 baseCoupon,,) = calc.calculateCoupon(premium, 5500, 1000);
        uint256 safety = calc.getSafetyMargin(5500);
        assertEq(safety, 200, "high vol safety = 200");
        assertLe(baseCoupon + safety, premium, "INV-1 violated: base + safety > premium");
        assertEq(baseCoupon, premium - safety, "base = premium - safety");
    }

    function test_INV1_midVol() public view {
        uint256 premium = 750;
        (uint256 baseCoupon,,) = calc.calculateCoupon(premium, 4000, 800);
        uint256 safety = calc.getSafetyMargin(4000);
        assertEq(safety, 150, "mid vol safety = 150");
        assertLe(baseCoupon + safety, premium, "INV-1 violated");
        assertEq(baseCoupon, premium - safety);
    }

    function test_INV1_lowVol() public view {
        uint256 premium = 500;
        (uint256 baseCoupon,,) = calc.calculateCoupon(premium, 2500, 600);
        uint256 safety = calc.getSafetyMargin(2500);
        assertEq(safety, 100, "low vol safety = 100");
        assertLe(baseCoupon + safety, premium, "INV-1 violated");
        assertEq(baseCoupon, premium - safety);
    }

    function testFuzz_INV1(uint256 premium, uint256 avgVol) public view {
        avgVol = bound(avgVol, 100, 15000);
        uint256 safety;
        if (avgVol >= 5000) safety = 200;
        else if (avgVol >= 3500) safety = 150;
        else safety = 100;
        premium = bound(premium, safety + 1, 1500);
        (uint256 baseCoupon,,) = calc.calculateCoupon(premium, avgVol, 500);
        assertLe(baseCoupon + safety, premium, "INV-1 fuzz violated");
    }

    function test_carryEnhance_normal() public view {
        (, uint256 enhance,) = calc.calculateCoupon(920, 5500, 1000);
        assertEq(enhance, 500, "carry capped at MAX_CARRY_ENHANCE");
    }

    function test_carryEnhance_belowCap() public view {
        (, uint256 enhance,) = calc.calculateCoupon(920, 5500, 500);
        assertEq(enhance, 350, "carry = 350 bps");
    }

    function test_carryEnhance_zero() public view {
        (, uint256 enhance,) = calc.calculateCoupon(920, 5500, 0);
        assertEq(enhance, 0, "zero carry rate -> zero enhance");
    }

    function test_totalCoupon() public view {
        (uint256 base, uint256 enhance, uint256 total) = calc.calculateCoupon(920, 5500, 1000);
        assertEq(base, 720);
        assertEq(enhance, 500);
        assertEq(total, 1220);
    }

    function test_calculateCouponAmount() public view {
        uint256 amount = calc.calculateCouponAmount(10000e6, 1220, 30);
        uint256 expected = (uint256(10000e6) * 1220 * 30) / (365 * 10000);
        assertEq(amount, expected);
        assertGt(amount, 0, "coupon amount should be > 0");
    }

    function test_calculateCouponAmount_fullYear() public view {
        uint256 amount = calc.calculateCouponAmount(1e6, 1000, 365);
        assertEq(amount, 100000, "10% of $1 = $0.10");
    }

    function test_revert_premiumBelowSafety() public {
        vm.expectRevert("premium <= safety margin");
        calc.calculateCoupon(100, 5500, 500);
    }

    function test_revert_premiumEqualSafety() public {
        vm.expectRevert("premium <= safety margin");
        calc.calculateCoupon(200, 5500, 500);
    }

    function test_constants() public view {
        assertEq(calc.SAFETY_MARGIN_HIGH_VOL(), 200);
        assertEq(calc.SAFETY_MARGIN_MID_VOL(), 150);
        assertEq(calc.SAFETY_MARGIN_LOW_VOL(), 100);
        assertEq(calc.CARRY_SHARE_RATE(), 7000);
        assertEq(calc.MAX_CARRY_ENHANCE(), 500);
    }
}
