# ICREConsumer
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/ICREConsumer.sol)


## Functions
### registerNoteParams


```solidity
function registerNoteParams(bytes32 noteId, PricingParams calldata params) external;
```

### getAcceptedPricing


```solidity
function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory);
```

