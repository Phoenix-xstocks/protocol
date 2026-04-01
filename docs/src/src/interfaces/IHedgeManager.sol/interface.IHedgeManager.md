# IHedgeManager
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IHedgeManager.sol)


## Functions
### openHedge


```solidity
function openHedge(bytes32 noteId, address[] calldata basket, uint256 notional) external;
```

### closeHedge


```solidity
function closeHedge(bytes32 noteId) external returns (uint256 recovered);
```

### rebalance


```solidity
function rebalance(bytes32 noteId) external;
```

### getDeltaDrift


```solidity
function getDeltaDrift(bytes32 noteId) external view returns (int256 driftBps);
```

