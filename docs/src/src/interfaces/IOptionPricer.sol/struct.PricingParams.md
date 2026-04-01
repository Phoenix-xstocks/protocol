# PricingParams
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IOptionPricer.sol)


```solidity
struct PricingParams {
    address[] basket;
    uint256 kiBarrierBps;
    uint256 couponBarrierBps;
    uint256 autocallTriggerBps;
    uint256 stepDownBps;
    uint256 maturityDays;
    uint256 numObservations;
}
```

