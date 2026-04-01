# Protocol Constants

All configurable parameters and their values.

## AutocallEngine

| Constant | Value | Description |
|----------|-------|-------------|
| `BPS` | 10,000 | Basis points denominator |
| `MAX_OBSERVATIONS` | 6 | Monthly observations over 180 days |
| `OBS_INTERVAL_DAYS` | 30 | Days between observations |
| `COUPON_BARRIER_BPS` | 7,000 | 70% worst-of coupon barrier |
| `AUTOCALL_TRIGGER_BPS` | 10,000 | 100% initial autocall trigger |
| `STEP_DOWN_BPS` | 200 | 2% step-down per observation |
| `KI_BARRIER_BPS` | 7,000 | 70% European knock-in barrier |
| `MATURITY_DAYS` | 180 | Note maturity (6 months) |
| `PRICE_MAX_STALENESS` | 24 hours | Maximum oracle price age |
| `KI_SETTLE_DEADLINE` | 7 days | Holder choice window on KI |

## XYieldVault

| Constant | Value | Description |
|----------|-------|-------------|
| `MIN_NOTE_SIZE` | 100 USDC | Minimum deposit |
| `MAX_NOTE_SIZE` | 100,000 USDC | Maximum deposit |
| `MAX_TVL` | 5,000,000 USDC | Phase 1 TVL cap |
| `MAX_ACTIVE_NOTES` | 500 | Maximum concurrent notes |
| `CLAIM_DEADLINE` | 24 hours | Time to claim after fulfillment |

## OptionPricer

| Constant | Value | Description |
|----------|-------|-------------|
| `TOLERANCE_HIGH_VOL` | 300 bps | MC vs on-chain tolerance (vol >= 50%) |
| `TOLERANCE_MID_VOL` | 200 bps | MC vs on-chain tolerance (vol 35-50%) |
| `TOLERANCE_LOW_VOL` | 150 bps | MC vs on-chain tolerance (vol < 35%) |
| `MIN_PREMIUM` | 300 bps | Minimum acceptable premium (3%) |
| `MAX_PREMIUM` | 1,500 bps | Maximum acceptable premium (15%) |
| `MAX_KI_PROB` | 1,500 bps | Maximum KI probability (15%) |

## CouponCalculator

| Constant | Value | Description |
|----------|-------|-------------|
| `SAFETY_MARGIN_HIGH_VOL` | 200 bps | Margin for vol >= 50% |
| `SAFETY_MARGIN_MID_VOL` | 150 bps | Margin for vol 35-50% |
| `SAFETY_MARGIN_LOW_VOL` | 100 bps | Margin for vol < 35% |
| `CARRY_SHARE_RATE` | 7,000 | 70% of carry to retail |
| `MAX_CARRY_ENHANCE` | 500 bps | 5% max carry enhancement |

## HedgeManager

| Constant | Value | Description |
|----------|-------|-------------|
| `DELTA_THRESHOLD_BPS` | 500 | 5% drift triggers rebalance |
| `DELTA_CRITICAL_BPS` | 1,500 | 15% drift triggers circuit breaker |
| `MAX_REBALANCE_COST` | 50 bps | 0.5% max rebalance cost |
| `DEFAULT_LEVERAGE` | 1 | 1x leverage (delta-neutral) |

## ReserveFund

| Constant | Value | Description |
|----------|-------|-------------|
| `TARGET_BPS` | 1,000 | 10% target reserve |
| `MINIMUM_BPS` | 300 | 3% minimum reserve |
| `CRITICAL_BPS` | 100 | 1% critical reserve |

## EpochManager

| Constant | Value | Description |
|----------|-------|-------------|
| `EPOCH_DURATION` | 48 hours | Epoch cycle length |
| `RESERVE_CONTRIBUTION_BPS` | 3,000 | 30% of surplus to reserve |

## FeeCollector

| Constant | Value | Description |
|----------|-------|-------------|
| `EMBEDDED_FEE_BPS` | 50 | 0.5% at deposit |
| `ORIGINATION_FEE_BPS` | 10 | 0.1% at deposit |
| `MANAGEMENT_FEE_BPS` | 25 | 0.25% annualized |
| `PERFORMANCE_FEE_BPS` | 1,000 | 10% of net carry |

## OneInchSwapper

| Constant | Value | Description |
|----------|-------|-------------|
| `MAX_RETRIES` | 3 | Swap retry attempts |
| `DEFAULT_SLIPPAGE_BPS` | 50 | 0.5% initial slippage |
| `RETRY_SLIPPAGE_INCREMENT` | 50 bps | +0.5% per retry |
