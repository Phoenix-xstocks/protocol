// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { ReserveFund } from "../../src/periphery/ReserveFund.sol";

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

contract ReserveFundTest is Test {
    ReserveFund public reserve;
    MockUSDC public usdc;
    address public owner;

    uint256 constant TOTAL_NOTIONAL = 1_000_000e6;

    function setUp() public {
        owner = address(this);
        usdc = new MockUSDC();
        reserve = new ReserveFund(address(usdc), owner);
    }

    function test_deposit() public {
        uint256 amount = 100_000e6;
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);

        reserve.deposit(amount);
        assertEq(reserve.getBalance(), amount);
    }

    function test_deposit_revert_zero() public {
        vm.expectRevert("zero deposit");
        reserve.deposit(0);
    }

    function test_getLevel_target() public {
        uint256 amount = 100_000e6; // 10% of $1M
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        uint256 level = reserve.getLevel(TOTAL_NOTIONAL);
        assertEq(level, 1000, "should be 10% = 1000 bps");
    }

    function test_getLevel_minimum() public {
        uint256 amount = 30_000e6; // 3%
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        assertEq(reserve.getLevel(TOTAL_NOTIONAL), 300);
    }

    function test_getLevel_critical() public {
        uint256 amount = 10_000e6; // 1%
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        assertEq(reserve.getLevel(TOTAL_NOTIONAL), 100);
    }

    function test_getLevel_zero_notional() public view {
        assertEq(reserve.getLevel(0), 10000);
    }

    function test_coverDeficit_full() public {
        uint256 depositAmount = 50_000e6;
        usdc.mint(owner, depositAmount);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);

        uint256 deficit = 20_000e6;
        uint256 covered = reserve.coverDeficit(deficit);
        assertEq(covered, deficit);
        assertEq(reserve.getBalance(), depositAmount - deficit);
    }

    function test_coverDeficit_partial() public {
        uint256 depositAmount = 10_000e6;
        usdc.mint(owner, depositAmount);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);

        uint256 covered = reserve.coverDeficit(20_000e6);
        assertEq(covered, depositAmount);
        assertEq(reserve.getBalance(), 0);
    }

    function test_coverDeficit_empty() public {
        uint256 covered = reserve.coverDeficit(10_000e6);
        assertEq(covered, 0);
    }

    function test_getHaircutRatio_above_critical() public {
        uint256 amount = 50_000e6; // 5%
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        assertEq(reserve.getHaircutRatio(TOTAL_NOTIONAL), 10000, "no haircut above critical");
    }

    function test_getHaircutRatio_at_critical() public {
        uint256 amount = 10_000e6; // 1%
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        assertEq(reserve.getHaircutRatio(TOTAL_NOTIONAL), 10000, "no haircut at critical");
    }

    function test_getHaircutRatio_below_critical() public {
        uint256 amount = 5_000e6; // 0.5%
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        assertEq(reserve.getHaircutRatio(TOTAL_NOTIONAL), 5000, "50% haircut at 0.5%");
    }

    function test_getHaircutRatio_near_zero() public {
        uint256 amount = 1_000e6; // 0.1%
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        assertEq(reserve.getHaircutRatio(TOTAL_NOTIONAL), 1000, "10% ratio at 0.1%");
    }

    function test_isBelowMinimum() public {
        uint256 amount = 20_000e6; // 2%
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        assertTrue(reserve.isBelowMinimum(TOTAL_NOTIONAL));
    }

    function test_isNotBelowMinimum() public {
        uint256 amount = 50_000e6; // 5%
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        assertFalse(reserve.isBelowMinimum(TOTAL_NOTIONAL));
    }

    function test_isCritical() public {
        uint256 amount = 5_000e6; // 0.5%
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        assertTrue(reserve.isCritical(TOTAL_NOTIONAL));
    }

    function test_isNotCritical() public {
        uint256 amount = 20_000e6; // 2%
        usdc.mint(owner, amount);
        usdc.approve(address(reserve), amount);
        reserve.deposit(amount);

        assertFalse(reserve.isCritical(TOTAL_NOTIONAL));
    }

    function test_onlyOwner_deposit() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        reserve.deposit(1000);
    }

    function test_onlyOwner_coverDeficit() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        reserve.coverDeficit(1000);
    }
}
