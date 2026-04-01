# IIssuanceGate
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IIssuanceGate.sol)


## Functions
### checkIssuance


```solidity
function checkIssuance(bytes32 noteId, uint256 notional, address[] calldata basket)
    external
    view
    returns (bool approved, string memory reason);
```

### noteActivated


```solidity
function noteActivated(uint256 notional) external;
```

### noteSettled


```solidity
function noteSettled(uint256 notional) external;
```

