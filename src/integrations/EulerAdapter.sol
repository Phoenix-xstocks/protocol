// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Minimal ERC-4626 interface for Euler V2 vaults
interface IEulerVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function balanceOf(address account) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function asset() external view returns (address);
    function maxDeposit(address) external view returns (uint256);
}

/// @title EulerAdapter
/// @notice Adapter for Euler V2 ERC-4626 vaults.
///         Used by ReserveFund to earn yield on idle USDC reserves.
///         Euler V2 uses the Euler Vault Kit (EVK) — permissionless vault deployment.
///
/// Integration points:
///   - ReserveFund deposits idle USDC → Euler USDC vault → earns lending yield
///   - On coverDeficit, withdraws from Euler back to cover coupon shortfalls
///   - Yield accrues passively via ERC-4626 share appreciation
contract EulerAdapter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IEulerVault public immutable eulerVault;
    IERC20 public immutable usdc;

    event Deposited(uint256 assets, uint256 shares);
    event Withdrawn(uint256 assets, uint256 shares);

    error VaultAssetMismatch();
    error InsufficientBalance();

    constructor(address _eulerVault, address _usdc, address _owner) Ownable(_owner) {
        require(_eulerVault != address(0), "zero vault");
        require(_usdc != address(0), "zero usdc");
        eulerVault = IEulerVault(_eulerVault);
        usdc = IERC20(_usdc);

        // Verify the Euler vault's underlying asset is USDC
        if (eulerVault.asset() != _usdc) revert VaultAssetMismatch();
    }

    /// @notice Deposit USDC into Euler vault to earn yield
    /// @param amount USDC amount to deposit
    /// @return shares Euler vault shares received
    function deposit(uint256 amount) external onlyOwner nonReentrant returns (uint256 shares) {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        usdc.safeIncreaseAllowance(address(eulerVault), amount);
        shares = eulerVault.deposit(amount, address(this));
        emit Deposited(amount, shares);
    }

    /// @notice Withdraw USDC from Euler vault
    /// @param amount USDC amount to withdraw
    /// @return shares Euler shares burned
    function withdraw(uint256 amount) external onlyOwner nonReentrant returns (uint256 shares) {
        shares = eulerVault.withdraw(amount, msg.sender, address(this));
        emit Withdrawn(amount, shares);
    }

    /// @notice Withdraw all USDC from Euler vault
    /// @return assets Total USDC withdrawn
    function withdrawAll() external onlyOwner nonReentrant returns (uint256 assets) {
        uint256 shares = eulerVault.balanceOf(address(this));
        if (shares == 0) return 0;
        assets = eulerVault.redeem(shares, msg.sender, address(this));
        emit Withdrawn(assets, shares);
    }

    /// @notice Get current USDC value of deposits in Euler (including yield)
    function getTotalValue() external view returns (uint256) {
        uint256 shares = eulerVault.balanceOf(address(this));
        return eulerVault.convertToAssets(shares);
    }

    /// @notice Get the yield earned (value above principal)
    function getAccruedYield(uint256 principal) external view returns (uint256) {
        uint256 totalValue = eulerVault.convertToAssets(eulerVault.balanceOf(address(this)));
        return totalValue > principal ? totalValue - principal : 0;
    }

    /// @notice Get Euler vault shares balance
    function getShares() external view returns (uint256) {
        return eulerVault.balanceOf(address(this));
    }

    /// @notice Recover tokens sent to this contract by mistake
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
