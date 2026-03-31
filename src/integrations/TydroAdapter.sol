// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ITydroAdapter } from "../interfaces/ITydroAdapter.sol";

/// @notice Minimal interface for Tydro aToken (Aave v3 fork).
interface IAToken {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Minimal interface for Tydro (Aave v3 fork) on Ink.
interface ITydroPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
        external
        returns (uint256);
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
    function getReserveNormalizedIncome(address asset) external view returns (uint256);
    function getCurrentLiquidityRate(address asset) external view returns (uint128);
    function getReserveData(address asset)
        external
        view
        returns (
            uint256 configuration,
            uint128 liquidityIndex,
            uint128 currentLiquidityRate2,
            uint128 variableBorrowIndex,
            uint128 currentVariableBorrowRate,
            uint128 currentStableBorrowRate,
            uint40 lastUpdateTimestamp,
            uint16 id,
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress,
            address interestRateStrategyAddress,
            uint128 accruedToTreasury,
            uint128 unbacked,
            uint128 isolationModeTotalDebt
        );
}

/// @title TydroAdapter
/// @notice Adapter for Tydro (Aave v3 fork on Ink). Manages collateral, borrowing, and lending.
contract TydroAdapter is ITydroAdapter, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ITydroPool public immutable tydroPool;
    IERC20 public immutable usdc;

    uint256 private constant VARIABLE_RATE_MODE = 2;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant RAY = 1e27;

    event CollateralDeposited(address indexed asset, uint256 amount);
    event CollateralWithdrawn(address indexed asset, uint256 amount);
    event USDCBorrowed(uint256 amount);
    event USDCRepaid(uint256 amount);
    event USDCDeposited(uint256 amount);
    event USDCWithdrawn(uint256 amount);

    constructor(address _tydroPool, address _usdc, address _owner) Ownable(_owner) {
        tydroPool = ITydroPool(_tydroPool);
        usdc = IERC20(_usdc);
    }

    /// @inheritdoc ITydroAdapter
    function depositCollateral(address asset, uint256 amount) external onlyOwner nonReentrant {
        IERC20(asset).forceApprove(address(tydroPool), amount);
        tydroPool.supply(asset, amount, address(this), 0);
        emit CollateralDeposited(asset, amount);
    }

    /// @inheritdoc ITydroAdapter
    function withdrawCollateral(address asset) external onlyOwner nonReentrant returns (uint256 amount) {
        amount = tydroPool.withdraw(asset, type(uint256).max, address(this));
        emit CollateralWithdrawn(asset, amount);
    }

    /// @inheritdoc ITydroAdapter
    function borrowUSDC(uint256 amount) external onlyOwner nonReentrant returns (uint256 borrowed) {
        tydroPool.borrow(address(usdc), amount, VARIABLE_RATE_MODE, 0, address(this));
        borrowed = amount;
        emit USDCBorrowed(amount);
    }

    /// @inheritdoc ITydroAdapter
    function repayUSDC(uint256 amount) external onlyOwner nonReentrant {
        usdc.forceApprove(address(tydroPool), amount);
        tydroPool.repay(address(usdc), amount, VARIABLE_RATE_MODE, address(this));
        emit USDCRepaid(amount);
    }

    /// @inheritdoc ITydroAdapter
    /// @notice Returns per-asset collateral value using the aToken balance
    function getCollateralValue(address asset) external view returns (uint256) {
        (,,,,,,, , address aTokenAddress,,,,,,) = tydroPool.getReserveData(asset);
        return IAToken(aTokenAddress).balanceOf(address(this));
    }

    /// @inheritdoc ITydroAdapter
    /// @notice Aave returns liquidity rate as a ray (1e27). Convert to wad (1e18) per-second.
    function getLendingRate() external view returns (uint256 ratePerSecond) {
        uint128 currentLiquidityRate = tydroPool.getCurrentLiquidityRate(address(usdc));
        // ray / seconds / (ray_to_wad) = wad per second
        ratePerSecond = uint256(currentLiquidityRate) / SECONDS_PER_YEAR / (RAY / 1e18);
    }

    /// @inheritdoc ITydroAdapter
    function depositUSDC(uint256 amount) external onlyOwner nonReentrant {
        usdc.forceApprove(address(tydroPool), amount);
        tydroPool.supply(address(usdc), amount, address(this), 0);
        emit USDCDeposited(amount);
    }

    /// @inheritdoc ITydroAdapter
    function withdrawUSDC(uint256 amount) external onlyOwner nonReentrant returns (uint256 withdrawn) {
        withdrawn = tydroPool.withdraw(address(usdc), amount, address(this));
        emit USDCWithdrawn(withdrawn);
    }

    /// @notice Recover tokens sent to this contract by mistake.
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
