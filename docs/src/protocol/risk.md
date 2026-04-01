# Risk Management

Phoenix employs multiple layers of risk control across issuance, hedging, reserves, and protocol operations.

## Issuance Gate (4 Pre-Checks)

Before any note transitions from `Priced` to `Active`, the `IssuanceGate` enforces:

| Check | Requirement | Rationale |
|-------|------------|-----------|
| **Pricing** | CRE pricing accepted | No note activates without validated fair value |
| **Reserve** | Reserve >= 3% of total notional | Ensures coupon buffer is healthy |
| **Note count** | Active notes < 500 | Limits protocol complexity |
| **Notional** | $100 <= notional <= $100k, TVL <= $5M | Phase 1 caps |

## Protocol Invariants

| ID | Invariant | Enforced By |
|----|-----------|-------------|
| INV-1 | `baseCoupon + safetyMargin <= premium` | CouponCalculator |
| INV-2 | `spotValue + perpPnL ~= notional (±5%)` | HedgeManager rebalance |
| INV-3 | `spotValue + perpPnL >= notional * 95%` | Delta drift threshold |
| INV-4 | State transitions follow defined table only | AutocallEngine._isValidTransition |
| INV-5 | P1-P6 waterfall order always respected | EpochManager.distributeWaterfall |
| INV-6 | No note goes active without issuance gate approval | AutocallEngine.activateNote |

## Price Oracle Safety

- **Staleness check**: 24-hour maximum on all price reads during observations
- **Dual oracle**: Chainlink Data Streams + Pyth Network
- **CRE cross-check**: MC results verified against on-chain analytical approximation
- **Vol oracle staleness**: 2-hour threshold with fallback values

## Hedge Risk Controls

| Risk | Control | Threshold |
|------|---------|-----------|
| Delta drift | Automatic rebalance | > 5% of notional |
| Critical drift | Circuit breaker (pause note) | > 15% of notional |
| Swap failure | 3x retry with increasing slippage | 0.5% → 1.0% → 1.5% |
| Rebalance cost | Per-rebalance cap | 0.5% of notional |

## Reserve Fund Levels

```
 10% ─── TARGET ─────── Healthy. Full carry enhancement paid.
  │
  3% ─── MINIMUM ────── Carry enhancement → 0. All carry to reserve.
  │                      100% of waterfall surplus → reserve.
  1% ─── CRITICAL ───── Haircut on carry enhancement.
  │                      reserve/1% = payout ratio.
  0% ─── DEPLETED ───── Base coupons may be delayed.
                         Emergency admin action needed.
```

## Failure Mode Fallbacks

| Scenario | Grace Period | Fallback | Impact |
|----------|-------------|----------|--------|
| Oracle stale | 24h | Permissionless fallback | 72h global pause if unresolved |
| Keeper late | 24h | Anyone can call observe() | Observation skipped after deadline |
| 1inch failure | 3 retries | USDC stays, skip rebalance | Note may be paused |
| Nado down | Active | Skip perp ops (testnet mode) | New issuance blocked |
| Tydro down | Keep positions | Deferred settlement (48h) | No immediate impact |
| CRE down | Fallback | OptionPricer alone for bounds | New issuance blocked |
| Euler down | Keep position | Use local USDC in reserve | Rebalance skipped |

## KI Settlement Protection

When knock-in occurs, the holder has a **7-day window** to choose between cash and physical delivery. If the holder doesn't act:

- Admin can force-settle as cash after 7 days
- This protects the protocol from indefinite open positions
- Physical delivery option lets holders bet on recovery
