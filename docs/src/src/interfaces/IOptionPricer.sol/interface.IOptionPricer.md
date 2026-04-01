# IOptionPricer
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IOptionPricer.sol)


## Functions
### verifyPricing


```solidity
function verifyPricing(PricingParams calldata params, uint256 mcPremiumBps, bytes32 mcHash)
    external
    view
    returns (bool approved, uint256 onChainApprox);
```

