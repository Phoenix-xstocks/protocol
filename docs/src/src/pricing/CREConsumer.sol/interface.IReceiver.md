# IReceiver
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/pricing/CREConsumer.sol)

Chainlink CRE IReceiver interface — consumer contracts must implement this.
The KeystoneForwarder calls onReport() after DON consensus.


## Functions
### onReport


```solidity
function onReport(bytes calldata metadata, bytes calldata report) external;
```

