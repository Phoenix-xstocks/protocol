// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IReserveFund } from "../interfaces/IReserveFund.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ReserveFund
/// @notice Buffer for coupon smoothing (Ethena model).
///         Levels: TARGET=10%, MINIMUM=3%, CRITICAL=1% of notional outstanding.
///         Dynamic haircut on carry enhancement when below critical.
contract ReserveFund is IReserveFund, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10000;
    uint256 public constant TARGET_BPS = 1000; // 10% of notional outstanding
    uint256 public constant MINIMUM_BPS = 300; // 3%
    uint256 public constant CRITICAL_BPS = 100; // 1%

    IERC20 public usdc;
    uint256 public balance;

    event Deposited(uint256 amount, uint256 newBalance);
    event DeficitCovered(uint256 requested, uint256 covered, uint256 newBalance);

    constructor(address _usdc, address _owner) Ownable(_owner) {
        require(_usdc != address(0), "zero usdc");
        usdc = IERC20(_usdc);
    }

    /// @inheritdoc IReserveFund
    function deposit(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "zero deposit");
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        balance += amount;
        emit Deposited(amount, balance);
    }

    /// @inheritdoc IReserveFund
    function coverDeficit(uint256 amount) external onlyOwner nonReentrant returns (uint256 covered) {
        covered = amount > balance ? balance : amount;
        if (covered > 0) {
            balance -= covered;
            usdc.safeTransfer(msg.sender, covered);
        }
        emit DeficitCovered(amount, covered, balance);
    }

    /// @inheritdoc IReserveFund
    function getBalance() external view returns (uint256) {
        return balance;
    }

    /// @inheritdoc IReserveFund
    /// @return levelBps Reserve level as bps of totalNotional
    function getLevel(uint256 totalNotional) external view returns (uint256 levelBps) {
        if (totalNotional == 0) return BPS; // 100% if no notional
        return (balance * BPS) / totalNotional;
    }

    /// @inheritdoc IReserveFund
    /// @notice Returns haircut ratio in BPS (10000 = no haircut, 5000 = 50% haircut)
    ///         haircut_ratio = reserve_balance / (1% * total_notional)
    ///         Only applies when reserve < CRITICAL (1%)
    function getHaircutRatio(uint256 totalNotional) external view returns (uint256 ratioBps) {
        if (totalNotional == 0) return BPS;

        uint256 levelBps = (balance * BPS) / totalNotional;

        // No haircut if above critical
        if (levelBps >= CRITICAL_BPS) return BPS;

        // haircut_ratio = balance / (1% * totalNotional) = levelBps / CRITICAL_BPS
        // Scaled to BPS: (levelBps * BPS) / CRITICAL_BPS
        return (levelBps * BPS) / CRITICAL_BPS;
    }

    /// @notice Check if reserve is below minimum (carry enhancement = 0 for new notes)
    function isBelowMinimum(uint256 totalNotional) external view returns (bool) {
        if (totalNotional == 0) return false;
        uint256 levelBps = (balance * BPS) / totalNotional;
        return levelBps < MINIMUM_BPS;
    }

    /// @notice Check if reserve is below critical (haircut existing carry + pause emissions)
    function isCritical(uint256 totalNotional) external view returns (bool) {
        if (totalNotional == 0) return false;
        uint256 levelBps = (balance * BPS) / totalNotional;
        return levelBps < CRITICAL_BPS;
    }
}
