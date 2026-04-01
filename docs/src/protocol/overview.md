# Protocol Overview

## The Product

Phoenix issues **Phoenix Autocall Notes** — structured products on baskets of 3 tokenized equities (xStocks) on the Ink chain (Kraken's L2, OP Stack). Each note has a 180-day maturity, pays monthly coupons when the worst-performing stock stays above 70%, and autocalls at par if performance is strong enough.

The xStocks universe includes: **NVDAx, TSLAx, METAx, AAPLx, MSFTx, AMZNx, GOOGLx**.

## Why On-Chain?

Traditional autocallable notes are sold by investment banks, involve opaque pricing, and are accessible only to accredited investors. Phoenix makes the same product:

- **Transparent** — pricing, hedging, and risk management are fully on-chain and auditable
- **Accessible** — deposits start at $100 USDC
- **Composable** — notes are ERC-1155 tokens, coupons stream via Sablier, yield accrues in Euler V2
- **Trustless** — no counterparty risk beyond smart contract risk; hedges are protocol-owned

## Architecture Layers

```
┌─────────────────────────────────────────────────────┐
│                     CORE LAYER                      │
│  XYieldVault (ERC-7540)  │  AutocallEngine  │ Note  │
├─────────────────────────────────────────────────────┤
│                   PRICING LAYER                     │
│  CREConsumer  │  OptionPricer  │  VolOracle  │ Calc │
├─────────────────────────────────────────────────────┤
│                    HEDGE LAYER                      │
│        HedgeManager         │      CarryEngine      │
├─────────────────────────────────────────────────────┤
│                  PERIPHERY LAYER                    │
│  EpochManager  │  FeeCollector  │  ReserveFund      │
├─────────────────────────────────────────────────────┤
│               INTEGRATIONS LAYER                    │
│ Chainlink │ Pyth │ 1inch │ Nado │ Tydro │ Euler    │
└─────────────────────────────────────────────────────┘
```

### Core Layer

- **XYieldVault** — ERC-7540 async deposit vault. Users deposit USDC, operators fulfill deposits by creating notes.
- **AutocallEngine** — 12-state machine managing note lifecycle from creation through settlement.
- **NoteToken** — Soulbound ERC-1155 representing note positions. Non-transferable in Phase 1.

### Pricing Layer

- **CREConsumer** — Receives Monte Carlo pricing from Chainlink CRE (20+ node DON).
- **OptionPricer** — On-chain worst-of put approximation for bounds checking MC results.
- **VolOracle** — Implied volatility and correlation data (CRE-fed with manual fallback).
- **CouponCalculator** — Computes coupon rates from premium, safety margin, and carry.
- **IssuanceGate** — 4 pre-checks before a note can go active (pricing, reserve, limits).

### Hedge Layer

- **HedgeManager** — Opens delta-neutral positions: buy xStocks spot, deposit as collateral on Tydro, short perps on Nado.
- **CarryEngine** — Aggregates carry from 3 sources: Nado funding, Tydro lending, collateral yield.

### Periphery Layer

- **EpochManager** — 48-hour cycles with strict P1-P6 waterfall distribution.
- **FeeCollector** — Collects embedded (0.5%), origination (0.1%), management (0.25% ann), and performance (10%) fees.
- **ReserveFund** — Coupon buffer following the Ethena model. Idle funds earn yield in Euler V2.

### Integrations Layer

Nine adapters connect the protocol to external DeFi protocols on Ink and cross-chain infrastructure.

## Access Control

| Role | Holder | Can Do |
|------|--------|--------|
| `DEFAULT_ADMIN_ROLE` | Multisig (3/5) | Deploy, upgrade, pause, set params |
| `KEEPER_ROLE` | CRE + permissionless | Observe, price, activate notes |
| `VAULT_ROLE` | XYieldVault | Create notes on AutocallEngine |
| `OPERATOR_ROLE` | Protocol operator | Fulfill deposits in vault |
| `MINTER_ROLE` / `BURNER_ROLE` | AutocallEngine | Mint/burn NoteTokens |
