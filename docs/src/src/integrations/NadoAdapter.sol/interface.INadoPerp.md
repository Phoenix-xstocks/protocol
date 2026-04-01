# INadoPerp
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/NadoAdapter.sol)

Minimal interface for Nado perp DEX on Ink.


## Functions
### openPosition


```solidity
function openPosition(uint256 pairIndex, bool isShort, uint256 notional, uint256 leverage, address margin)
    external
    returns (bytes32 positionId);
```

### closePosition


```solidity
function closePosition(bytes32 positionId) external returns (int256 pnl);
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

