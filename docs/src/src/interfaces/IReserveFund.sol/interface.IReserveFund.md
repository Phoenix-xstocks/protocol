# IReserveFund
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IReserveFund.sol)


## Functions
### deposit


```solidity
function deposit(uint256 amount) external;
```

### coverDeficit


```solidity
function coverDeficit(uint256 amount) external returns (uint256 covered);
```

### getBalance


```solidity
function getBalance() external view returns (uint256);
```

### getLevel


```solidity
function getLevel(uint256 totalNotional) external view returns (uint256 levelBps);
```

### getHaircutRatio


```solidity
function getHaircutRatio(uint256 totalNotional) external view returns (uint256 ratioBps);
```

### isBelowMinimum


```solidity
function isBelowMinimum(uint256 totalNotional) external view returns (bool);
```

### isCritical


```solidity
function isCritical(uint256 totalNotional) external view returns (bool);
```

