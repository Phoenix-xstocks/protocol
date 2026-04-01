# IVolOracle
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IVolOracle.sol)


## Functions
### updateVols


```solidity
function updateVols(address[] calldata assets, uint256[] calldata volsBps, uint256[] calldata correlationsBps)
    external;
```

### getVol


```solidity
function getVol(address asset) external view returns (uint256 volBps);
```

### getAvgCorrelation


```solidity
function getAvgCorrelation(address[] calldata basket) external view returns (uint256 avgCorrBps);
```

### getLastUpdate


```solidity
function getLastUpdate() external view returns (uint256 timestamp);
```

