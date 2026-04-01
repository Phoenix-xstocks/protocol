// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { TydroAdapter, ITydroPool } from "../../src/integrations/TydroAdapter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 {
    string public name = "Mock USDC";
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

contract MockAToken {
    mapping(address => uint256) public balanceOf;

    function setBalance(address account, uint256 amount) external {
        balanceOf[account] = amount;
    }
}

contract MockTydroPool {
    uint256 public totalCollateral;
    uint128 public liquidityRate;
    mapping(address => address) public aTokens;

    function setCollateral(uint256 amount) external {
        totalCollateral = amount;
    }

    function setLiquidityRate(uint128 rate) external {
        liquidityRate = rate;
    }

    function setAToken(address asset, address aToken) external {
        aTokens[asset] = aToken;
    }

    function supply(address asset, uint256 amount, address, uint16) external {
        // Pull tokens from caller (adapter) like the real Aave pool
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        totalCollateral += amount;
    }

    function withdraw(address asset, uint256, address to) external returns (uint256) {
        uint256 amount = totalCollateral;
        totalCollateral = 0;
        // Send tokens to `to` like the real Aave pool
        MockERC20(asset).mint(to, amount);
        return amount;
    }

    function borrow(address asset, uint256 amount, uint256, uint16, address) external {
        // Mint borrowed tokens to caller (adapter)
        MockERC20(asset).mint(msg.sender, amount);
    }

    function repay(address asset, uint256 amount, uint256, address) external returns (uint256) {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        return amount;
    }

    function getUserAccountData(address)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return (totalCollateral, 0, 0, 0, 0, 1e18);
    }

    function getReserveNormalizedIncome(address) external pure returns (uint256) {
        return 1e27; // 1 RAY
    }

    function getCurrentLiquidityRate(address) external view returns (uint128) {
        return liquidityRate;
    }

    function getReserveData(address asset)
        external
        view
        returns (
            uint256, uint128, uint128, uint128, uint128, uint128,
            uint40, uint16, address, address, address, address,
            uint128, uint128, uint128
        )
    {
        return (0, 0, 0, 0, 0, 0, 0, 0, aTokens[asset], address(0), address(0), address(0), 0, 0, 0);
    }
}

contract TydroAdapterTest is Test {
    TydroAdapter public adapter;
    MockTydroPool public mockPool;
    MockERC20 public usdc;
    MockERC20 public xStock;
    MockAToken public aToken;
    address public owner = address(this);

    function setUp() public {
        mockPool = new MockTydroPool();
        usdc = new MockERC20();
        xStock = new MockERC20();
        aToken = new MockAToken();
        adapter = new TydroAdapter(address(mockPool), address(usdc), owner);

        // Register aToken for xStock asset
        mockPool.setAToken(address(xStock), address(aToken));

        // Fund the caller (owner) and approve adapter to pull tokens
        usdc.mint(owner, 100_000e6);
        xStock.mint(owner, 1_000e18);
        usdc.approve(address(adapter), type(uint256).max);
        xStock.approve(address(adapter), type(uint256).max);
    }

    function test_depositCollateral() public {
        adapter.depositCollateral(address(xStock), 500e18);
        assertEq(mockPool.totalCollateral(), 500e18);
    }

    function test_withdrawCollateral() public {
        adapter.depositCollateral(address(xStock), 500e18);
        uint256 withdrawn = adapter.withdrawCollateral(address(xStock));
        assertEq(withdrawn, 500e18);
        // Tokens should be at the caller (owner), not the adapter
        assertEq(xStock.balanceOf(owner), 1_000e18); // 500 remaining + 500 withdrawn
    }

    function test_borrowUSDC() public {
        uint256 borrowed = adapter.borrowUSDC(5_000e6);
        assertEq(borrowed, 5_000e6);
    }

    function test_repayUSDC() public {
        // Borrow first so adapter has USDC to repay
        adapter.borrowUSDC(5_000e6);
        adapter.repayUSDC(5_000e6);
    }

    function test_depositUSDC() public {
        adapter.depositUSDC(10_000e6);
        assertEq(mockPool.totalCollateral(), 10_000e6);
    }

    function test_withdrawUSDC() public {
        adapter.depositUSDC(10_000e6);
        uint256 withdrawn = adapter.withdrawUSDC(10_000e6);
        assertEq(withdrawn, 10_000e6);
        // USDC should be at the caller (owner)
        assertEq(usdc.balanceOf(owner), 100_000e6); // 90k remaining + 10k withdrawn
    }

    function test_getCollateralValue() public {
        // Set aToken balance to simulate deposited collateral
        aToken.setBalance(address(adapter), 500e18);
        uint256 value = adapter.getCollateralValue(address(xStock));
        assertEq(value, 500e18);
    }

    function test_getLendingRate() public {
        // Set liquidity rate to 5% per year in RAY (5e25)
        mockPool.setLiquidityRate(5e25);
        uint256 ratePerSecond = adapter.getLendingRate();
        // 5e25 / 31536000 ~ 1.585e18
        assertGt(ratePerSecond, 0, "rate should be positive");
    }

    function test_onlyOwner_depositCollateral() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        adapter.depositCollateral(address(xStock), 500e18);
    }

    function test_onlyOwner_borrowUSDC() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        adapter.borrowUSDC(5_000e6);
    }

    function test_recoverToken() public {
        MockERC20 stray = new MockERC20();
        stray.mint(address(adapter), 1000e6);
        adapter.recoverToken(address(stray), 1000e6);
        assertEq(stray.balanceOf(owner), 1000e6);
    }
}
