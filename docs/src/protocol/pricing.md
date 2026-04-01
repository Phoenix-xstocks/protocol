# Pricing

Phoenix uses a three-layer pricing architecture that combines off-chain Monte Carlo simulation with on-chain verification. This ensures fair pricing while maintaining trustlessness.

## Three Layers of Security

```
┌──────────────────────────────────────────────────────────┐
│  Layer 1: Off-Chain Monte Carlo (10,000 paths)           │
│  → Fair value put premium, KI probability, Greeks        │
├──────────────────────────────────────────────────────────┤
│  Layer 2: Chainlink CRE Consensus (20+ node DON)        │
│  → Each node runs MC independently, BFT consensus        │
├──────────────────────────────────────────────────────────┤
│  Layer 3: On-Chain Verification (OptionPricer)           │
│  → Bounds check + cross-check vs analytical approx       │
└──────────────────────────────────────────────────────────┘
```

### Layer 1: Monte Carlo Simulation

The off-chain pricing engine runs 10,000 Geometric Brownian Motion paths with Cholesky-decomposed correlations:

- **Inputs**: spot prices, implied volatilities, pairwise correlations, barriers, time to maturity
- **RNG**: deterministic ChaCha20 with `seed = keccak256(blockHash, noteId)`
- **Output**: `PricingResult` containing put premium (bps), KI probability, expected KI loss, and vega

### Layer 2: Chainlink CRE

Chainlink's Confidential Reporting Engine runs the Monte Carlo independently on 20+ nodes:

1. `RequestPricing` event triggers the CRE workflow
2. Each node fetches inputs and runs the MC simulation
3. Byzantine fault-tolerant consensus produces a single result
4. Result is written to `CREConsumer` via the KeystoneForwarder

### Layer 3: On-Chain Verification

The `OptionPricer` contract performs an analytical worst-of put approximation:

```
singlePut   = BS_approx(avgVol, KI_barrier, T)
worstOfMult = sqrt(basket_size)
corrAdj     = 1 - (avgCorrelation / 20000)
onChainApprox = singlePut * worstOfMult * corrAdj  (annualized)
```

The MC result must fall within a vol-dependent tolerance band:

| Average Volatility | Tolerance |
|-------------------|-----------|
| >= 50% (high) | 3.00% (300 bps) |
| >= 35% (mid) | 2.00% (200 bps) |
| < 35% (low) | 1.50% (150 bps) |

Hard bounds: premium must be within **3% — 15%** (300-1500 bps), KI probability <= 15%.

## PricingResult Structure

```solidity
struct PricingResult {
    uint16 putPremiumBps;       // fair value, annualized
    uint16 kiProbabilityBps;    // probability of KI breach
    uint16 expectedKILossBps;   // expected loss if KI occurs
    uint16 vegaBps;             // volatility sensitivity
    bytes32 inputsHash;         // hash of MC inputs for verification
}
```

## Volatility Oracle

The `VolOracle` provides implied volatilities and pairwise correlations:

- **Primary source**: Chainlink CRE data feeds (implements `IReceiver`)
- **Fallback**: Manual updates by `UPDATER_ROLE` if CRE data is stale
- **Staleness threshold**: 2 hours (configurable)
- **Vol range**: 0 — 200% (0 — 20,000 bps)
- **Correlation range**: 0 — 100% (0 — 10,000 bps)

## Coupon Calculation

Once pricing is accepted, the `CouponCalculator` determines the coupon rate:

```
baseCoupon    = premium - safetyMargin
carryEnhance  = min(carryRate * 70% / 10000, 500 bps)
totalCoupon   = baseCoupon + carryEnhance
```

**Safety margins** (vol-dependent):
- High vol (>= 50%): 200 bps
- Mid vol (>= 35%): 150 bps
- Low vol (< 35%): 100 bps

**Per-observation coupon amount:**
```
couponUSDC = notional * totalCouponBps * 30 / (365 * 10000)
```

## Testnet Mode

On testnet, `priceNoteDirect()` bypasses CRE and lets the operator supply prices and premium directly. This is controlled by `AutocallEngine.testnetMode`.
