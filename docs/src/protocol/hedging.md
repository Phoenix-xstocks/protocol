# Delta-Neutral Hedging

The `HedgeManager` constructs a delta-neutral position for each note, ensuring the protocol is market-neutral and profits from carry rather than directional exposure.

## Hedge Structure

For each xStock in a note's basket:

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Buy xStock │────►│ Deposit on   │────►│ Short perp  │
│  spot (1x)  │     │ Tydro as     │     │ on Nado     │
│  via 1inch  │     │ collateral   │     │ (1x lever)  │
└─────────────┘     └──────────────┘     └─────────────┘
       │                    │                    │
       │              Borrow USDC           Earn funding
       │              for margin            (longs pay shorts)
       │                    │                    │
       └────── DELTA = 0 ──┴────────────────────┘
```

**Spot long + Perp short = Delta-neutral.** The protocol earns carry from the short perp funding rate, Tydro USDC lending, and collateral yield.

## Opening a Hedge

When `activateNote()` is called:

1. USDC is split equally across basket assets (`notional / basket.length`)
2. For each asset:
   - Swap USDC → xStock via 1inch (with retry up to 1.5% slippage)
   - Deposit xStock as collateral on Tydro
   - Open a 1x short perp on Nado
3. Borrow USDC from Tydro (using collateral) for perp margin

## Closing a Hedge

At settlement (autocall, maturity, or KI):

1. Close all Nado short positions
2. Repay Tydro USDC borrow
3. Withdraw xStock collateral from Tydro
4. Sell xStocks back to USDC via 1inch
5. Return recovered USDC to AutocallEngine for payout

## Delta Drift Monitoring

The protocol monitors the gap between spot value and perp notional:

```
drift = |spotValue - perpValue| / notional * 10000
```

| Drift Level | Threshold | Action |
|------------|-----------|--------|
| Normal | < 5% (500 bps) | No action |
| Rebalance | >= 5% (500 bps) | Adjust perp sizes to re-center delta |
| Critical | >= 15% (1500 bps) | Circuit breaker — pause the note |

Rebalance cost is capped at **0.5%** of notional per rebalance event.

## Carry Engine

The `CarryEngine` aggregates income from three sources:

| Source | Adapter | ~Share | Typical Range |
|--------|---------|--------|---------------|
| **Funding rate** | Nado perp shorts | ~55% | 5-20% annualized |
| **USDC lending** | Tydro pool | ~35% | 4-6% annualized |
| **Collateral yield** | Tydro xStock | ~10% | 1-3% annualized |

Carry is collected per note and fed into the coupon enhancement formula:

```
carryEnhance = min(totalCarryRate * 70% / 10000, 500 bps)
```

This means retail holders receive up to 70% of carry income, capped at 5% annualized enhancement. The remaining carry flows through the epoch waterfall.

## Example Carry Regimes

| Scenario | Funding | Lending | Total | Enhancement | Coupon |
|----------|---------|---------|-------|-------------|--------|
| Bull market | 10% | 5% | ~15% | 5.0% (cap) | ~12.5% |
| Normal | 5% | 5% | ~10% | 3.0% | ~10.5% |
| Bear market | -2% | 5% | ~3% | 1.0% | ~8.5% |

Floor coupon is approximately **8.5%**, always above risk-free rate.

## Testnet Mode

On Ink Sepolia, Nado perps are not available. `HedgeManager.testnetMode` skips all Nado operations while keeping Tydro collateral operations active.
