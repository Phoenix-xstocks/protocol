# INadoAdapter
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/INadoAdapter.sol)


## Functions
### openShort


```solidity
function openShort(uint256 pairIndex, uint256 notional, uint256 leverage) external returns (bytes32 positionId);
```

### closeShort


```solidity
function closeShort(bytes32 positionId) external returns (uint256 pnl);
```

### claimFunding


```solidity
function claimFunding(bytes32 positionId) external returns (uint256 fundingAmount);
```

### getPosition


```solidity
function getPosition(bytes32 positionId)
    external
    view
    returns (int256 unrealizedPnl, uint256 margin, uint256 size, uint256 accumulatedFunding);
```

