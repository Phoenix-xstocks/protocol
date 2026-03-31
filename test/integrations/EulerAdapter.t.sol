// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { ReserveFund } from "../../src/periphery/ReserveFund.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ERC-4626 Euler vault for testing
contract MockEulerVault {
    ERC20 public immutable underlying;
    mapping(address => uint256) public shares;
    uint256 public totalShares;
    uint256 public totalDeposited;

    // Simulate 5% APY by inflating assets slightly
    uint256 public yieldMultiplier = 10500; // 105% = 5% yield

    constructor(address _asset) {
        underlying = ERC20(_asset);
    }

    function asset() external view returns (address) { return address(underlying); }

    function deposit(uint256 assets, address receiver) external returns (uint256 _shares) {
        underlying.transferFrom(msg.sender, address(this), assets);
        _shares = assets; // 1:1 for simplicity
        shares[receiver] += _shares;
        totalShares += _shares;
        totalDeposited += assets;
        return _shares;
    }

    function withdraw(uint256 assets, address receiver, address owner_) external returns (uint256 _shares) {
        _shares = convertToShares(assets);
        require(shares[owner_] >= _shares, "insufficient shares");
        shares[owner_] -= _shares;
        totalShares -= _shares;
        underlying.transfer(receiver, assets);
        return _shares;
    }

    function redeem(uint256 _shares, address receiver, address owner_) external returns (uint256 assets) {
        require(shares[owner_] >= _shares, "insufficient shares");
        assets = convertToAssets(_shares);
        shares[owner_] -= _shares;
        totalShares -= _shares;
        underlying.transfer(receiver, assets);
        return assets;
    }

    function balanceOf(address account) external view returns (uint256) { return shares[account]; }

    function convertToAssets(uint256 _shares) public view returns (uint256) {
        if (totalShares == 0) return _shares;
        return (_shares * totalDeposited * yieldMultiplier) / (totalShares * 10000);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalDeposited == 0) return assets;
        return (assets * totalShares * 10000) / (totalDeposited * yieldMultiplier);
    }

    function setYieldMultiplier(uint256 mult) external { yieldMultiplier = mult; }
}

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}
    function mint(address to, uint256 amt) external { _mint(to, amt); }
    function decimals() public pure override returns (uint8) { return 6; }
}

contract EulerReserveFundTest is Test {
    ReserveFund public reserve;
    MockUSDC public usdc;
    MockEulerVault public eulerVault;
    address public owner;

    function setUp() public {
        owner = address(this);
        usdc = new MockUSDC();
        eulerVault = new MockEulerVault(address(usdc));
        reserve = new ReserveFund(address(usdc), owner);

        // Fund the mock euler vault with USDC for withdrawals
        usdc.mint(address(eulerVault), 1_000_000e6);
    }

    function test_setEulerVault() public {
        reserve.setEulerVault(address(eulerVault));
        assertEq(address(reserve.eulerVault()), address(eulerVault));
    }

    function test_depositToEuler() public {
        reserve.setEulerVault(address(eulerVault));

        // First deposit USDC into reserve
        usdc.mint(owner, 100_000e6);
        usdc.approve(address(reserve), 100_000e6);
        reserve.deposit(100_000e6);

        // Then move to Euler
        reserve.depositToEuler(50_000e6);

        assertEq(reserve.eulerPrincipal(), 50_000e6);
        assertEq(eulerVault.balanceOf(address(reserve)), 50_000e6);
    }

    function test_getTotalValue_includes_euler() public {
        reserve.setEulerVault(address(eulerVault));

        usdc.mint(owner, 100_000e6);
        usdc.approve(address(reserve), 100_000e6);
        reserve.deposit(100_000e6);

        reserve.depositToEuler(50_000e6);

        // Local: 50k, Euler: 50k * 105% = 52.5k
        uint256 total = reserve.getTotalValue();
        assertGt(total, 100_000e6, "total should include Euler yield");
    }

    function test_coverDeficit_pulls_from_euler() public {
        reserve.setEulerVault(address(eulerVault));

        usdc.mint(owner, 100_000e6);
        usdc.approve(address(reserve), 100_000e6);
        reserve.deposit(100_000e6);

        // Move all to Euler
        reserve.depositToEuler(100_000e6);
        assertEq(usdc.balanceOf(address(reserve)), 0, "reserve should have 0 local USDC");

        // Cover deficit — should pull from Euler
        uint256 covered = reserve.coverDeficit(50_000e6);
        assertEq(covered, 50_000e6, "should cover from Euler");
    }

    function test_getEulerYield() public {
        reserve.setEulerVault(address(eulerVault));

        usdc.mint(owner, 100_000e6);
        usdc.approve(address(reserve), 100_000e6);
        reserve.deposit(100_000e6);

        reserve.depositToEuler(100_000e6);

        // With 5% yield multiplier: yield = 100k * 5% = 5k
        uint256 yield_ = reserve.getEulerYield();
        assertEq(yield_, 5_000e6, "5% yield on 100k");
    }

    function test_getLevel_with_euler() public {
        reserve.setEulerVault(address(eulerVault));

        uint256 notional = 1_000_000e6;

        usdc.mint(owner, 100_000e6); // 10% of notional
        usdc.approve(address(reserve), 100_000e6);
        reserve.deposit(100_000e6);

        reserve.depositToEuler(100_000e6);

        // Total value = 100k * 1.05 = 105k = 10.5% of 1M
        uint256 level = reserve.getLevel(notional);
        assertEq(level, 1050, "level should be 10.5% (1050 bps)");
        assertFalse(reserve.isBelowMinimum(notional));
        assertFalse(reserve.isCritical(notional));
    }

    function test_withdrawFromEuler() public {
        reserve.setEulerVault(address(eulerVault));

        usdc.mint(owner, 100_000e6);
        usdc.approve(address(reserve), 100_000e6);
        reserve.deposit(100_000e6);

        reserve.depositToEuler(100_000e6);
        reserve.withdrawFromEuler(50_000e6);

        assertEq(reserve.eulerPrincipal(), 50_000e6);
        assertEq(usdc.balanceOf(address(reserve)), 50_000e6);
    }

    function test_no_euler_vault_works_normally() public {
        // Without setting Euler vault, reserve works as before
        usdc.mint(owner, 100_000e6);
        usdc.approve(address(reserve), 100_000e6);
        reserve.deposit(100_000e6);

        uint256 total = reserve.getTotalValue();
        assertEq(total, 100_000e6);

        uint256 yield_ = reserve.getEulerYield();
        assertEq(yield_, 0);
    }
}
