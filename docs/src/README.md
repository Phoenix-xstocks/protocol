# Phoenix Protocol

Phoenix is a structured product protocol that brings **autocallable notes** on-chain. It lets retail users earn ~12% annualized yield on baskets of tokenized equities (xStocks) while the protocol manages delta-neutral hedging, coupon payments, and risk entirely on-chain.

## What is an Autocallable Note?

An autocallable note is a structured financial product tied to a basket of underlying assets. It pays periodic coupons as long as the underlying assets stay above a barrier, and automatically settles ("autocalls") if they perform well enough at any observation date.

Phoenix implements a **worst-of autocall with European knock-in barrier and memory coupons** — one of the most popular structured product formats in traditional finance, now fully on-chain.

## How It Works

```
Deposit USDC ─── Vault mints Note ─── Monthly observations ─── Settlement
     │                  │                      │                    │
     │           Protocol hedges          Coupon paid           Principal
     │           delta-neutral            if basket              returned
     │           (spot + perps)           above 70%             at par
     │                                                              │
     └──── Fees deducted ────────────────────────── or KI loss ─────┘
```

1. **Deposit**: Users deposit USDC into the XYieldVault
2. **Note Creation**: The protocol creates an autocall note linked to a basket of 3 xStocks
3. **Pricing**: Chainlink CRE runs Monte Carlo simulations; on-chain verification confirms the result
4. **Hedging**: HedgeManager opens a delta-neutral position (spot long + perp short)
5. **Observations**: Every 30 days, the protocol checks the worst-performing stock
6. **Coupons**: If the worst performer is above 70%, a coupon is paid (streamed via Sablier)
7. **Settlement**: At maturity or autocall, principal is returned; if knock-in occurs, the holder chooses cash or physical delivery

## Key Parameters

| Parameter | Value |
|-----------|-------|
| Maturity | 180 days (6 monthly observations) |
| Autocall trigger | 100% of initial, stepping down 2% per observation |
| Coupon barrier | 70% of initial (worst-of) |
| Knock-in barrier | 70% European (checked at maturity only) |
| Target coupon | ~12% annualized (base + carry enhancement) |
| Deposit range | $100 — $100,000 USDC |
| TVL cap | $5,000,000 (Phase 1) |
| Chain | Ink (Kraken L2, OP Stack) |

## Protocol Architecture

The protocol is organized into five layers:

- **Core** — Note lifecycle, vault, token representation
- **Pricing** — Monte Carlo validation, volatility oracle, coupon math
- **Hedge** — Delta-neutral hedging, carry collection
- **Periphery** — Fee collection, reserve fund, epoch waterfall
- **Integrations** — Adapters for Chainlink, Pyth, 1inch, Nado, Tydro, Euler, Sablier
