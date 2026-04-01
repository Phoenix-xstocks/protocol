# CouponCalculator
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/pricing/CouponCalculator.sol)

**Inherits:**
[ICouponCalculator](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/ICouponCalculator.sol/interface.ICouponCalculator.md)

Computes coupon rates for Phoenix Autocall notes.
base = premium - safety_margin (dynamic, vol-linked)
carry_enhance = min(carry_rate * share / BPS, MAX_CARRY_ENHANCE)
total = base + enhance


## State Variables
### BPS

```solidity
uint256 public constant BPS = 10000;
```


### SAFETY_MARGIN_HIGH_VOL

```solidity
uint256 public constant SAFETY_MARGIN_HIGH_VOL = 200;
```


### SAFETY_MARGIN_MID_VOL

```solidity
uint256 public constant SAFETY_MARGIN_MID_VOL = 150;
```


### SAFETY_MARGIN_LOW_VOL

```solidity
uint256 public constant SAFETY_MARGIN_LOW_VOL = 100;
```


### CARRY_SHARE_RATE

```solidity
uint256 public constant CARRY_SHARE_RATE = 7000;
```


### MAX_CARRY_ENHANCE

```solidity
uint256 public constant MAX_CARRY_ENHANCE = 500;
```


## Functions
### calculateCoupon


```solidity
function calculateCoupon(uint256 optionPremiumBps, uint256 avgVolBps, uint256 carryRateBps)
    external
    pure
    returns (uint256 baseCouponBps, uint256 carryEnhanceBps, uint256 totalCouponBps);
```

### calculateCouponAmount


```solidity
function calculateCouponAmount(uint256 notional, uint256 totalCouponBps, uint256 obsIntervalDays)
    external
    pure
    returns (uint256 couponAmount);
```

### getSafetyMargin


```solidity
function getSafetyMargin(uint256 avgVolBps) external pure returns (uint256);
```

### _getSafetyMargin


```solidity
function _getSafetyMargin(uint256 avgVolBps) internal pure returns (uint256);
```

