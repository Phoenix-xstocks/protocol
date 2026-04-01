# IPriceFeed
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/core/AutocallEngine.sol)

Minimal interface for reading latest verified prices.


## Functions
### getLatestPrice


```solidity
function getLatestPrice(bytes32 feedId) external view returns (int192 price, uint32 timestamp);
```

