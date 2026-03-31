// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { FeeCollector } from "../../src/periphery/FeeCollector.sol";

contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract FeeCollectorTest is Test {
    FeeCollector public collector;
    MockUSDC public usdc;

    address owner = address(this);
    address treasury = address(0xBEEF);
    address nonOwner = address(0xDEAD);

    function setUp() public {
        usdc = new MockUSDC();
        collector = new FeeCollector(address(usdc), treasury, owner);
    }

    /// @dev Mint USDC to owner and approve the collector to spend it
    function _fundOwner(uint256 amount) internal {
        usdc.mint(owner, amount);
        usdc.approve(address(collector), amount);
    }

    // ---------------------------------------------------------------
    // collectEmbeddedFee: 0.5% of notional
    // ---------------------------------------------------------------
    function test_collectEmbeddedFee_correctAmount() public {
        uint256 notional = 1_000_000e6; // $1M
        _fundOwner(notional);

        uint256 fee = collector.collectEmbeddedFee(notional);

        // 0.5% = 50 bps -> 1_000_000 * 50 / 10_000 = 5_000
        assertEq(fee, 5_000e6, "embedded fee should be 0.5%");
    }

    function test_collectEmbeddedFee_transfersToTreasury() public {
        uint256 notional = 1_000_000e6;
        _fundOwner(notional);

        uint256 treasuryBefore = usdc.balanceOf(treasury);
        collector.collectEmbeddedFee(notional);
        uint256 treasuryAfter = usdc.balanceOf(treasury);

        assertEq(treasuryAfter - treasuryBefore, 5_000e6, "treasury should receive fee");
    }

    function test_collectEmbeddedFee_updatesTotalCollected() public {
        uint256 notional = 1_000_000e6;
        _fundOwner(notional);

        collector.collectEmbeddedFee(notional);
        assertEq(collector.totalCollected(), 5_000e6);
    }

    function test_collectEmbeddedFee_emitsEvent() public {
        uint256 notional = 1_000_000e6;
        _fundOwner(notional);

        vm.expectEmit(false, false, false, true);
        emit FeeCollector.EmbeddedFeeCollected(notional, 5_000e6);
        collector.collectEmbeddedFee(notional);
    }

    function test_collectEmbeddedFee_zeroNotional() public {
        uint256 fee = collector.collectEmbeddedFee(0);
        assertEq(fee, 0);
        assertEq(collector.totalCollected(), 0);
    }

    function test_collectEmbeddedFee_smallNotional() public {
        // 100 USDC -> fee = 100e6 * 50 / 10000 = 500000 = 0.5 USDC
        uint256 notional = 100e6;
        _fundOwner(notional);

        uint256 fee = collector.collectEmbeddedFee(notional);
        assertEq(fee, 500000, "0.5% of 100 USDC = 0.5 USDC");
    }

    // ---------------------------------------------------------------
    // collectOriginationFee: 0.1% of notional
    // ---------------------------------------------------------------
    function test_collectOriginationFee_correctAmount() public {
        uint256 notional = 1_000_000e6;
        _fundOwner(notional);

        uint256 fee = collector.collectOriginationFee(notional);

        // 0.1% = 10 bps -> 1_000_000 * 10 / 10_000 = 1_000
        assertEq(fee, 1_000e6, "origination fee should be 0.1%");
    }

    function test_collectOriginationFee_transfersToTreasury() public {
        uint256 notional = 1_000_000e6;
        _fundOwner(notional);

        uint256 treasuryBefore = usdc.balanceOf(treasury);
        collector.collectOriginationFee(notional);
        uint256 treasuryAfter = usdc.balanceOf(treasury);

        assertEq(treasuryAfter - treasuryBefore, 1_000e6);
    }

    function test_collectOriginationFee_emitsEvent() public {
        uint256 notional = 1_000_000e6;
        _fundOwner(notional);

        vm.expectEmit(false, false, false, true);
        emit FeeCollector.OriginationFeeCollected(notional, 1_000e6);
        collector.collectOriginationFee(notional);
    }

    function test_collectOriginationFee_zeroNotional() public {
        uint256 fee = collector.collectOriginationFee(0);
        assertEq(fee, 0);
    }

    // ---------------------------------------------------------------
    // collectManagementFee: 0.25% annualized, pro-rata
    // ---------------------------------------------------------------
    function test_collectManagementFee_fullYear() public {
        uint256 notional = 1_000_000e6;
        uint256 elapsed = 365 days;
        // fee = notional * 25 * 365days / (10000 * 365days) = notional * 25 / 10000
        // = 1_000_000 * 25 / 10000 = 2_500 USDC
        uint256 expectedFee = 2_500e6;
        _fundOwner(expectedFee);

        uint256 fee = collector.collectManagementFee(notional, elapsed);
        assertEq(fee, expectedFee, "full year management fee = 0.25% of notional");
    }

    function test_collectManagementFee_halfYear() public {
        uint256 notional = 1_000_000e6;
        uint256 elapsed = 365 days / 2; // ~182.5 days
        // fee = 1_000_000e6 * 25 * (365days/2) / (10000 * 365days)
        // = 1_000_000e6 * 25 / 20000 = 1_250e6
        uint256 expectedFee = 1_250e6;
        _fundOwner(expectedFee);

        uint256 fee = collector.collectManagementFee(notional, elapsed);
        assertEq(fee, expectedFee, "half year management fee = 0.125% of notional");
    }

    function test_collectManagementFee_48hEpoch() public {
        uint256 notional = 1_000_000e6;
        uint256 elapsed = 48 hours;
        // fee = notional * 25 * 172800 / (10000 * 31536000)
        uint256 expectedFee = (notional * 25 * 48 hours) / (10000 * 365 days);
        _fundOwner(expectedFee);

        uint256 fee = collector.collectManagementFee(notional, elapsed);
        assertEq(fee, expectedFee, "48h epoch pro-rata fee");
        assertGt(fee, 0, "fee should be positive for 48h epoch");
    }

    function test_collectManagementFee_transfersToTreasury() public {
        uint256 notional = 1_000_000e6;
        uint256 elapsed = 365 days;
        uint256 expectedFee = 2_500e6;
        _fundOwner(expectedFee);

        uint256 treasuryBefore = usdc.balanceOf(treasury);
        collector.collectManagementFee(notional, elapsed);
        uint256 treasuryAfter = usdc.balanceOf(treasury);

        assertEq(treasuryAfter - treasuryBefore, expectedFee);
    }

    function test_collectManagementFee_emitsEvent() public {
        uint256 notional = 1_000_000e6;
        uint256 elapsed = 365 days;
        uint256 expectedFee = 2_500e6;
        _fundOwner(expectedFee);

        vm.expectEmit(false, false, false, true);
        emit FeeCollector.ManagementFeeCollected(notional, elapsed, expectedFee);
        collector.collectManagementFee(notional, elapsed);
    }

    function test_collectManagementFee_zeroElapsed() public {
        uint256 fee = collector.collectManagementFee(1_000_000e6, 0);
        assertEq(fee, 0, "zero elapsed = zero fee");
    }

    function test_collectManagementFee_zeroNotional() public {
        uint256 fee = collector.collectManagementFee(0, 365 days);
        assertEq(fee, 0);
    }

    // ---------------------------------------------------------------
    // collectPerformanceFee: 10% of carry net
    // ---------------------------------------------------------------
    function test_collectPerformanceFee_correctAmount() public {
        uint256 carryNet = 100_000e6; // $100K net carry
        // 10% = 1000 bps -> 100_000 * 1000 / 10000 = 10_000
        uint256 expectedFee = 10_000e6;
        _fundOwner(expectedFee);

        uint256 fee = collector.collectPerformanceFee(carryNet);
        assertEq(fee, expectedFee, "performance fee should be 10% of carry");
    }

    function test_collectPerformanceFee_transfersToTreasury() public {
        uint256 carryNet = 50_000e6;
        uint256 expectedFee = 5_000e6;
        _fundOwner(expectedFee);

        uint256 treasuryBefore = usdc.balanceOf(treasury);
        collector.collectPerformanceFee(carryNet);
        uint256 treasuryAfter = usdc.balanceOf(treasury);

        assertEq(treasuryAfter - treasuryBefore, expectedFee);
    }

    function test_collectPerformanceFee_emitsEvent() public {
        uint256 carryNet = 100_000e6;
        uint256 expectedFee = 10_000e6;
        _fundOwner(expectedFee);

        vm.expectEmit(false, false, false, true);
        emit FeeCollector.PerformanceFeeCollected(carryNet, expectedFee);
        collector.collectPerformanceFee(carryNet);
    }

    function test_collectPerformanceFee_zeroCarry() public {
        uint256 fee = collector.collectPerformanceFee(0);
        assertEq(fee, 0);
    }

    function test_collectPerformanceFee_smallCarry() public {
        // 10 USDC carry -> 1 USDC fee
        uint256 carryNet = 10e6;
        uint256 expectedFee = 1e6;
        _fundOwner(expectedFee);

        uint256 fee = collector.collectPerformanceFee(carryNet);
        assertEq(fee, expectedFee);
    }

    // ---------------------------------------------------------------
    // Only owner can call
    // ---------------------------------------------------------------
    function test_collectEmbeddedFee_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        collector.collectEmbeddedFee(1_000e6);
    }

    function test_collectOriginationFee_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        collector.collectOriginationFee(1_000e6);
    }

    function test_collectManagementFee_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        collector.collectManagementFee(1_000e6, 48 hours);
    }

    function test_collectPerformanceFee_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        collector.collectPerformanceFee(1_000e6);
    }

    // ---------------------------------------------------------------
    // Treasury receives funds (cumulative)
    // ---------------------------------------------------------------
    function test_treasuryReceivesCumulativeFees() public {
        uint256 notional = 1_000_000e6;
        // Embedded: 5_000e6, Origination: 1_000e6
        uint256 totalNeeded = 6_000e6;
        _fundOwner(totalNeeded);

        collector.collectEmbeddedFee(notional);
        collector.collectOriginationFee(notional);

        assertEq(usdc.balanceOf(treasury), 6_000e6, "treasury should receive both fees");
        assertEq(collector.totalCollected(), 6_000e6, "total collected should be cumulative");
    }

    function test_getTotalCollected() public {
        assertEq(collector.getTotalCollected(), 0, "initially zero");

        uint256 notional = 1_000_000e6;
        _fundOwner(5_000e6);
        collector.collectEmbeddedFee(notional);
        assertEq(collector.getTotalCollected(), 5_000e6);
    }

    // ---------------------------------------------------------------
    // setTreasury
    // ---------------------------------------------------------------
    function test_setTreasury() public {
        address newTreasury = address(0xCAFE);
        collector.setTreasury(newTreasury);
        assertEq(collector.treasury(), newTreasury);
    }

    function test_setTreasury_emitsEvent() public {
        address newTreasury = address(0xCAFE);
        vm.expectEmit(false, false, false, true);
        emit FeeCollector.TreasuryUpdated(newTreasury);
        collector.setTreasury(newTreasury);
    }

    function test_setTreasury_revertsOnZero() public {
        vm.expectRevert("zero treasury");
        collector.setTreasury(address(0));
    }

    function test_setTreasury_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        collector.setTreasury(address(0xCAFE));
    }

    function test_setTreasury_feesGoToNewTreasury() public {
        address newTreasury = address(0xCAFE);
        collector.setTreasury(newTreasury);

        uint256 notional = 1_000_000e6;
        _fundOwner(5_000e6);
        collector.collectEmbeddedFee(notional);

        assertEq(usdc.balanceOf(newTreasury), 5_000e6, "fee should go to new treasury");
        assertEq(usdc.balanceOf(treasury), 0, "old treasury should have nothing");
    }

    // ---------------------------------------------------------------
    // Constructor validations
    // ---------------------------------------------------------------
    function test_constructor_revertsZeroUsdc() public {
        vm.expectRevert("zero usdc");
        new FeeCollector(address(0), treasury, owner);
    }

    function test_constructor_revertsZeroTreasury() public {
        vm.expectRevert("zero treasury");
        new FeeCollector(address(usdc), address(0), owner);
    }

    // ---------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------
    function test_constants() public view {
        assertEq(collector.BPS(), 10000);
        assertEq(collector.EMBEDDED_FEE_BPS(), 50);
        assertEq(collector.ORIGINATION_FEE_BPS(), 10);
        assertEq(collector.MANAGEMENT_FEE_BPS(), 25);
        assertEq(collector.PERFORMANCE_FEE_BPS(), 1000);
        assertEq(collector.SECONDS_PER_YEAR(), 365 days);
    }
}
