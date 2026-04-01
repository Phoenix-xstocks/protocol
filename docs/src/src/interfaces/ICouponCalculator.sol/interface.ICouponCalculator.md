# ICouponCalculator
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/ICouponCalculator.sol)


## Functions
### calculateCoupon


```solidity
function calculateCoupon(uint256 optionPremiumBps, uint256 avgVolBps, uint256 carryRateBps)
    external
    view
    returns (uint256 baseCouponBps, uint256 carryEnhanceBps, uint256 totalCouponBps);
```

### calculateCouponAmount


```solidity
function calculateCouponAmount(uint256 notional, uint256 totalCouponBps, uint256 obsIntervalDays)
    external
    pure
    returns (uint256 couponAmount);
```

