// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { FeeCollector } from "../../src/periphery/FeeCollector.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function decimals() public pure override returns (uint8) { return 6; }
}

contract FeeCollectorTest is Test {
    FeeCollector public fc;
    MockUSDC public usdc;
    address public treasury = address(0xBEEF);
    address public owner;
    address public caller;

    function setUp() public {
        owner = address(this);
        caller = address(this);
        usdc = new MockUSDC();
        fc = new FeeCollector(address(usdc), treasury, owner);
    }

    // ================================================================
    // Embedded fee: 0.5%
    // ================================================================

    function test_embeddedFee_correct_amount() public {
        uint256 notional = 10_000e6;
        usdc.mint(caller, notional);
        usdc.approve(address(fc), notional);

        uint256 fee = fc.collectEmbeddedFee(notional);
        // 0.5% of 10000 = 50 USDC
        assertEq(fee, 50e6, "embedded fee = 0.5%");
        assertEq(usdc.balanceOf(treasury), 50e6, "treasury received fee");
    }

    function test_embeddedFee_zero_notional() public {
        uint256 fee = fc.collectEmbeddedFee(0);
        assertEq(fee, 0);
    }

    // ================================================================
    // Origination fee: 0.1%
    // ================================================================

    function test_originationFee_correct_amount() public {
        uint256 notional = 10_000e6;
        usdc.mint(caller, notional);
        usdc.approve(address(fc), notional);

        uint256 fee = fc.collectOriginationFee(notional);
        // 0.1% of 10000 = 10 USDC
        assertEq(fee, 10e6, "origination fee = 0.1%");
        assertEq(usdc.balanceOf(treasury), 10e6);
    }

    // ================================================================
    // Management fee: 0.25% annualized, pro-rata
    // ================================================================

    function test_managementFee_48h_epoch() public {
        uint256 notional = 1_000_000e6;
        uint256 elapsed = 48 hours;

        // 0.25% ann * 48h / 365d = ~13.70 USDC on $1M
        usdc.mint(caller, 100e6);
        usdc.approve(address(fc), 100e6);

        uint256 fee = fc.collectManagementFee(notional, elapsed);
        // (1_000_000e6 * 25 * 172800) / (10000 * 31536000) = 13698... ~13.7 USDC
        assertApproxEqAbs(fee, 13698e3, 1e3, "management fee ~13.7 USDC per 48h on $1M");
        assertEq(usdc.balanceOf(treasury), fee);
    }

    function test_managementFee_fullYear() public {
        uint256 notional = 1_000_000e6;
        uint256 elapsed = 365 days;

        usdc.mint(caller, 10_000e6);
        usdc.approve(address(fc), 10_000e6);

        uint256 fee = fc.collectManagementFee(notional, elapsed);
        // 0.25% of $1M = $2500
        assertApproxEqAbs(fee, 2500e6, 1e6, "management fee = 0.25% ann");
    }

    // ================================================================
    // Performance fee: 10% of carry net
    // ================================================================

    function test_performanceFee_correct_amount() public {
        uint256 carryNet = 10_000e6; // $10k carry this epoch

        usdc.mint(caller, carryNet);
        usdc.approve(address(fc), carryNet);

        uint256 fee = fc.collectPerformanceFee(carryNet);
        // 10% of 10000 = 1000 USDC
        assertEq(fee, 1_000e6, "performance fee = 10% of carry");
        assertEq(usdc.balanceOf(treasury), 1_000e6);
    }

    // ================================================================
    // Access control
    // ================================================================

    function test_onlyOwner_embeddedFee() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        fc.collectEmbeddedFee(10_000e6);
    }

    function test_onlyOwner_originationFee() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        fc.collectOriginationFee(10_000e6);
    }

    function test_onlyOwner_managementFee() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        fc.collectManagementFee(10_000e6, 48 hours);
    }

    function test_onlyOwner_performanceFee() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        fc.collectPerformanceFee(10_000e6);
    }

    // ================================================================
    // Total collected tracking
    // ================================================================

    function test_totalCollected_accumulates() public {
        uint256 notional = 10_000e6;
        usdc.mint(caller, notional);
        usdc.approve(address(fc), notional);

        fc.collectEmbeddedFee(notional);
        fc.collectOriginationFee(notional);

        // 50 + 10 = 60 USDC
        assertEq(fc.totalCollected(), 60e6, "total collected = embedded + origination");
    }

    // ================================================================
    // Treasury getter
    // ================================================================

    function test_treasury_returns_address() public view {
        assertEq(fc.treasury(), treasury);
    }

    // ================================================================
    // Fuzz: fees always proportional to notional
    // ================================================================

    function testFuzz_embeddedFee_proportional(uint256 notional) public {
        notional = bound(notional, 0, 100_000_000e6); // up to $100M
        usdc.mint(caller, notional);
        usdc.approve(address(fc), notional);

        uint256 fee = fc.collectEmbeddedFee(notional);
        uint256 expected = (notional * 50) / 10000;
        assertEq(fee, expected, "embedded fee always 0.5%");
    }
}
