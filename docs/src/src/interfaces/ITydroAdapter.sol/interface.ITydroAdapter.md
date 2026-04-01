# ITydroAdapter
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/ITydroAdapter.sol)


## Functions
### depositCollateral


```solidity
function depositCollateral(address asset, uint256 amount) external;
```

### withdrawCollateral


```solidity
function withdrawCollateral(address asset) external returns (uint256 amount);
```

### borrowUSDC


```solidity
function borrowUSDC(uint256 amount) external returns (uint256 borrowed);
```

### repayUSDC


```solidity
function repayUSDC(uint256 amount) external;
```

### getCollateralValue


```solidity
function getCollateralValue(address asset) external view returns (uint256);
```

### getLendingRate


```solidity
function getLendingRate() external view returns (uint256 ratePerSecond);
```

### depositUSDC


```solidity
function depositUSDC(uint256 amount) external;
```

### withdrawUSDC


```solidity
function withdrawUSDC(uint256 amount) external returns (uint256 withdrawn);
```

