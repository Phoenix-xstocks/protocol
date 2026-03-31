// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IReserveFund } from "../interfaces/IReserveFund.sol";
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
    function asset() external view returns (address);
}

/// @title ReserveFund
/// @notice Buffer for coupon smoothing (Ethena model) with Euler V2 yield.
///         Idle USDC reserves are deposited into Euler V2 vault to earn lending yield.
///         On deficit, withdraws from Euler to cover coupon shortfalls.
///         Levels: TARGET=10%, MINIMUM=3%, CRITICAL=1% of notional outstanding.
contract ReserveFund is IReserveFund, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10000;
    uint256 public constant TARGET_BPS = 1000; // 10% of notional outstanding
    uint256 public constant MINIMUM_BPS = 300; // 3%
    uint256 public constant CRITICAL_BPS = 100; // 1%

    IERC20 public usdc;
    uint256 public balance; // total principal deposited (not including Euler yield)

    /// @notice Euler V2 vault for yield on idle reserves (optional)
    IEulerVault public eulerVault;
    uint256 public eulerPrincipal; // USDC principal deposited into Euler

    event Deposited(uint256 amount, uint256 newBalance);
    event DeficitCovered(uint256 requested, uint256 covered, uint256 newBalance);
    event EulerVaultSet(address vault);
    event DepositedToEuler(uint256 amount, uint256 shares);
    event WithdrawnFromEuler(uint256 amount);

    constructor(address _usdc, address _owner) Ownable(_owner) {
        require(_usdc != address(0), "zero usdc");
        usdc = IERC20(_usdc);
    }

    /// @notice Set the Euler V2 vault for yield generation. Admin only.
    function setEulerVault(address _eulerVault) external onlyOwner {
        eulerVault = IEulerVault(_eulerVault);
        emit EulerVaultSet(_eulerVault);
    }

    /// @notice Deposit idle USDC into Euler vault for yield
    function depositToEuler(uint256 amount) external onlyOwner nonReentrant {
        require(address(eulerVault) != address(0), "no euler vault");
        require(amount <= usdc.balanceOf(address(this)), "insufficient USDC");

        usdc.safeIncreaseAllowance(address(eulerVault), amount);
        eulerVault.deposit(amount, address(this));
        eulerPrincipal += amount;
        emit DepositedToEuler(amount, eulerVault.balanceOf(address(this)));
    }

    /// @notice Withdraw USDC from Euler vault back to reserve
    function withdrawFromEuler(uint256 amount) external onlyOwner nonReentrant {
        require(address(eulerVault) != address(0), "no euler vault");
        eulerVault.withdraw(amount, address(this), address(this));
        if (amount <= eulerPrincipal) {
            eulerPrincipal -= amount;
        } else {
            eulerPrincipal = 0;
        }
        emit WithdrawnFromEuler(amount);
    }

    /// @notice Get total reserve value including Euler yield
    function getTotalValue() public view returns (uint256) {
        uint256 localBalance = usdc.balanceOf(address(this));
        uint256 eulerValue = address(eulerVault) != address(0)
            ? eulerVault.convertToAssets(eulerVault.balanceOf(address(this)))
            : 0;
        return localBalance + eulerValue;
    }

    /// @inheritdoc IReserveFund
    function deposit(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "zero deposit");
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        balance += amount;
        emit Deposited(amount, balance);
    }

    /// @inheritdoc IReserveFund
    /// @notice Covers deficit by first using local USDC, then withdrawing from Euler if needed.
    function coverDeficit(uint256 amount) external onlyOwner nonReentrant returns (uint256 covered) {
        uint256 localBal = usdc.balanceOf(address(this));

        if (localBal >= amount) {
            // Enough local USDC
            covered = amount;
        } else {
            // Pull shortfall from Euler
            uint256 shortfall = amount - localBal;
            if (address(eulerVault) != address(0) && eulerVault.balanceOf(address(this)) > 0) {
                eulerVault.withdraw(shortfall, address(this), address(this));
                if (shortfall <= eulerPrincipal) {
                    eulerPrincipal -= shortfall;
                } else {
                    eulerPrincipal = 0;
                }
            }
            uint256 availableNow = usdc.balanceOf(address(this));
            covered = amount > availableNow ? availableNow : amount;
        }

        if (covered > 0) {
            balance = covered <= balance ? balance - covered : 0;
            usdc.safeTransfer(msg.sender, covered);
        }
        emit DeficitCovered(amount, covered, balance);
    }

    /// @inheritdoc IReserveFund
    /// @notice Returns total value (local USDC + Euler deposits including yield)
    function getBalance() external view returns (uint256) {
        return getTotalValue();
    }

    /// @inheritdoc IReserveFund
    /// @return levelBps Reserve level as bps of totalNotional (includes Euler yield)
    function getLevel(uint256 totalNotional) external view returns (uint256 levelBps) {
        if (totalNotional == 0) return BPS;
        return (getTotalValue() * BPS) / totalNotional;
    }

    /// @inheritdoc IReserveFund
    /// @notice Returns haircut ratio in BPS (10000 = no haircut, 5000 = 50% haircut)
    function getHaircutRatio(uint256 totalNotional) external view returns (uint256 ratioBps) {
        if (totalNotional == 0) return BPS;
        uint256 levelBps = (getTotalValue() * BPS) / totalNotional;
        if (levelBps >= CRITICAL_BPS) return BPS;
        return (levelBps * BPS) / CRITICAL_BPS;
    }

    /// @notice Check if reserve is below minimum (includes Euler value)
    function isBelowMinimum(uint256 totalNotional) external view returns (bool) {
        if (totalNotional == 0) return false;
        return (getTotalValue() * BPS) / totalNotional < MINIMUM_BPS;
    }

    /// @notice Check if reserve is below critical (includes Euler value)
    function isCritical(uint256 totalNotional) external view returns (bool) {
        if (totalNotional == 0) return false;
        return (getTotalValue() * BPS) / totalNotional < CRITICAL_BPS;
    }

    /// @notice Get yield earned from Euler (value above principal)
    function getEulerYield() external view returns (uint256) {
        if (address(eulerVault) == address(0)) return 0;
        uint256 eulerValue = eulerVault.convertToAssets(eulerVault.balanceOf(address(this)));
        return eulerValue > eulerPrincipal ? eulerValue - eulerPrincipal : 0;
    }
}
