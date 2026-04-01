# Note Lifecycle

Every Phoenix Autocall Note moves through a 12-state machine managed by the `AutocallEngine`. This page describes each state and the transitions between them.

## State Machine

```
Created ──── priceNote() ────► Priced ──── activateNote() ────► Active
  │                              │                                │
  │ cancel()                     │ cancel()                       │ observe()
  ▼                              ▼                                ▼
Cancelled                    Cancelled                    ObservationPending
                                                                  │
                                          ┌───────────────────────┼───────────────┐
                                          │                       │               │
                                          ▼                       ▼               ▼
                                     Autocalled              Active          MaturityCheck
                                          │              (continue)              │
                                          │                              ┌───────┴───────┐
                                          ▼                              ▼               ▼
                                       Settled ◄─────────────── NoKISettle          KISettle
                                          │                                             │
                                          │                                    settleKI()
                                          ▼                                             │
                                        Rolled                                   Settled
```

Emergency paths: `Active ↔ EmergencyPaused` (admin only).

## States

| State | Description |
|-------|-------------|
| `Created` | Note exists, awaiting CRE pricing |
| `Priced` | Monte Carlo pricing accepted, awaiting activation |
| `Active` | Hedge is open, observations running |
| `ObservationPending` | Transitional state during observe() |
| `Autocalled` | Worst-of hit autocall trigger; settling at par |
| `MaturityCheck` | Last observation completed; checking KI |
| `NoKISettle` | No knock-in at maturity; settling at par |
| `KISettle` | Knock-in breached; holder has 7 days to choose |
| `Settled` | Note fully settled, NoteToken burned |
| `Rolled` | Settled note rolled into a new product (ERC-7579) |
| `EmergencyPaused` | Temporarily paused by admin |
| `Cancelled` | Note cancelled before activation |

## Note Data Structure

```solidity
struct Note {
    address[] basket;              // 3 xStock token addresses
    uint256   notional;            // USDC notional amount
    address   holder;              // note holder address
    State     state;               // current lifecycle state
    uint8     observations;        // completed observations (0-6)
    uint256   memoryCoupon;        // accumulated unpaid coupons (USDC)
    uint256   totalCouponBps;      // annual coupon rate (base + carry)
    uint256   baseCouponBps;       // base coupon rate (premium - margin)
    uint256   createdAt;           // creation timestamp
    uint256   maturityDate;        // createdAt + 180 days
    uint256   lastObservationTime; // last observation timestamp
    uint256   kiSettleStartTime;   // KI settlement window start
    int256[]  initialPrices;       // spot prices at activation (8 decimals)
}
```

## Observation Logic

Observations occur every 30 days. At each observation, the protocol:

1. **Gets worst-of performance** — fetches current prices for all basket assets, computes `performance = current / initial`, takes the minimum
2. **Checks autocall trigger** — trigger starts at 100% and steps down 2% per observation (100%, 98%, 96%, 94%, 92%, 90%)
3. **If autocall triggers** — pays all coupons (current + memory), closes hedge, returns principal at par
4. **Checks coupon barrier** — if worst-of >= 70%, coupon is paid (or streamed via Sablier)
5. **If coupon missed** — base coupon amount is accumulated as memory coupon
6. **At observation 6** — maturity check: if worst-of >= 70% KI barrier, settle at par; otherwise enter KI settlement

## Memory Coupons

When the worst-performing stock drops below the 70% coupon barrier at an observation, the coupon is not lost — it accumulates as a "memory coupon". When the basket recovers above 70% at a future observation, all accumulated memory coupons are paid out alongside the current coupon.

```
Obs 1: worst-of = 75% → coupon paid           (memory = 0)
Obs 2: worst-of = 65% → coupon missed         (memory = 1 coupon)
Obs 3: worst-of = 60% → coupon missed         (memory = 2 coupons)
Obs 4: worst-of = 80% → coupon paid + 2 memory (memory = 0)
```

## Settlement Paths

### Autocall Settlement
If worst-of performance >= autocall trigger at any observation, the note autocalls:
- All pending coupons (current + memory) are paid
- Hedge is closed
- Principal returned at par (100% of notional)

### Maturity — No Knock-In
If the note reaches maturity (observation 6) and worst-of >= 70%:
- Final coupon paid
- Any remaining memory coupons paid
- Hedge closed, principal returned at par

### Maturity — Knock-In (European)
If worst-of < 70% at the final observation:
- The holder enters a **7-day choice window**
- **Cash settlement**: receive `notional * worst_performance%` in USDC
- **Physical delivery**: receive equivalent value in the worst-performing xStock (allows holding for recovery)
- If the holder doesn't choose within 7 days, admin force-settles as cash
