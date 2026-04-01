# IFeeCollector
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IFeeCollector.sol)


## Functions
### collectEmbeddedFee


```solidity
function collectEmbeddedFee(uint256 notional) external returns (uint256 fee);
```

### collectOriginationFee


```solidity
function collectOriginationFee(uint256 notional) external returns (uint256 fee);
```

### collectManagementFee


```solidity
function collectManagementFee(uint256 notional, uint256 elapsed) external returns (uint256 fee);
```

### collectPerformanceFee


```solidity
function collectPerformanceFee(uint256 carryNet) external returns (uint256 fee);
```

### getTotalCollected


```solidity
function getTotalCollected() external view returns (uint256);
```

### treasury


```solidity
function treasury() external view returns (address);
```

