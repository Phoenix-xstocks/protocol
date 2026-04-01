# IEpochManager
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IEpochManager.sol)


## Functions
### getCurrentEpoch


```solidity
function getCurrentEpoch() external view returns (uint256);
```

### getEpochStart


```solidity
function getEpochStart(uint256 epochId) external view returns (uint256 timestamp);
```

### advanceEpoch


```solidity
function advanceEpoch() external;
```

### distributeWaterfall


```solidity
function distributeWaterfall() external;
```

### isEpochReady


```solidity
function isEpochReady() external view returns (bool);
```

