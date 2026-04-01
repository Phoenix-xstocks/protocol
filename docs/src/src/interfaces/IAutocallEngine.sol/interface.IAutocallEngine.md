# IAutocallEngine
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IAutocallEngine.sol)


## Functions
### createNote


```solidity
function createNote(address[] calldata basket, uint256 notional, address holder) external returns (bytes32 noteId);
```

### observe


```solidity
function observe(bytes32 noteId) external;
```

### settleKI


```solidity
function settleKI(bytes32 noteId, bool preferPhysical) external;
```

### getState


```solidity
function getState(bytes32 noteId) external view returns (State);
```

### getNoteCount


```solidity
function getNoteCount() external view returns (uint256);
```

