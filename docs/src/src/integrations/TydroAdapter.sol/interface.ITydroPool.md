# ITydroPool
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/TydroAdapter.sol)

Minimal interface for Tydro (Aave v3 fork) on Ink.


## Functions
### supply


```solidity
function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
```

### withdraw


```solidity
function withdraw(address asset, uint256 amount, address to) external returns (uint256);
```

### borrow


```solidity
function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
    external;
```

### repay


```solidity
function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
    external
    returns (uint256);
```

### getUserAccountData


```solidity
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
```

### getReserveNormalizedIncome


```solidity
function getReserveNormalizedIncome(address asset) external view returns (uint256);
```

### getCurrentLiquidityRate


```solidity
function getCurrentLiquidityRate(address asset) external view returns (uint128);
```

### getReserveData


```solidity
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
```

