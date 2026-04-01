# Epoch Waterfall

The `EpochManager` runs **48-hour epoch cycles** that collect protocol revenue and distribute it through a strict priority waterfall. This ensures coupon payments are always prioritized over protocol profits.

## Epoch Cycle

```
Epoch N starts
    │
    ├── Collect carry from all active notes (CarryEngine)
    ├── Collect fees due this epoch (FeeCollector)
    ├── Check delta drift per active note (HedgeManager)
    │   └── Trigger rebalance if drift > 5%
    │
    └── distributeWaterfall()
         │
         ├── P1: Base coupons        (SENIOR)
         ├── P2: Principal repayment  (SENIOR)
         ├── P3: Carry enhancement    (MEZZANINE)
         ├── P4: Hedge costs          (JUNIOR)
         ├── P5: Reserve contribution (JUNIOR)
         └── P6: Protocol treasury    (EQUITY)
```

## Priority Levels

### P1 — Base Coupons (Senior)

Base coupon payments due to note holders. **Always paid first.** If available cash is insufficient, the ReserveFund covers the deficit.

**Invariant: P6 is NEVER paid if P1 is not fully covered.**

### P2 — Principal Repayment (Senior)

Principal owed to settling notes. Covered by hedge close proceeds.

### P3 — Carry Enhancement (Mezzanine)

The retail share of carry income. Subject to **haircut** if the reserve fund is below critical level (1%):

```
if reserve < 1%:
    P3_actual = P3_due * (reserve_level / 1%)
```

Example: reserve at 0.5% → carry enhancement paid at 50%.

### P4 — Hedge Operational Costs (Junior)

Costs from rebalancing, swap slippage, and position management.

### P5 — Reserve Fund Contribution (Junior)

Replenishes the reserve fund:
- **Normal mode**: 30% of remaining cash goes to reserve
- **Below minimum** (reserve < 3%): 100% of remaining cash goes to reserve

### P6 — Protocol Treasury (Equity)

Whatever remains after P1-P5 goes to the protocol treasury. This is **blocked entirely** if P1 was not fully paid in this epoch.

## Reserve Fund

The reserve fund follows the **Ethena model** — a buffer that absorbs coupon payment risk:

| Level | Threshold | Effect |
|-------|-----------|--------|
| **Target** | 10% of notional | Healthy state |
| **Minimum** | 3% of notional | Carry enhancement set to 0; new issuance may be restricted |
| **Critical** | 1% of notional | Haircut applied to carry enhancement; emergency measures |

### Yield Generation

Idle USDC in the reserve fund is deposited into **Euler V2** (ERC-4626 vault) for lending yield. The total reserve value includes both local USDC and Euler vault shares.

### Deficit Coverage

When P1 cash is insufficient:
1. Use local USDC balance in ReserveFund
2. If still insufficient, withdraw from Euler V2
3. Transfer covered amount to EpochManager

## Fee Structure

Fees are collected by the `FeeCollector` and flow into the waterfall:

| Fee | Rate | When | From |
|-----|------|------|------|
| Embedded | 0.5% | At deposit | Notional |
| Origination | 0.1% | At deposit | Notional |
| Management | 0.25% annualized | Per epoch (pro-rata) | TVL |
| Performance | 10% | Per epoch | Net carry |
