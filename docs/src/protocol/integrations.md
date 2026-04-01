# Integrations

Phoenix connects to 8 external protocols through dedicated adapter contracts. Each adapter abstracts protocol-specific logic behind a clean interface.

## Protocol Map

```
                          ┌─────────────┐
                          │   Phoenix   │
                          │   Protocol  │
                          └──────┬──────┘
            ┌──────┬──────┬──────┼──────┬──────┬──────┬──────┐
            ▼      ▼      ▼      ▼      ▼      ▼      ▼      ▼
         Chainlink  Pyth  1inch  Nado  Tydro  Euler  Sablier  CRE
         DataStr.  Oracle  Agg.  Perps  Lend  Vault  Stream  Pricing
```

## Chainlink Data Streams

**Contract**: `ChainlinkPriceFeed`

Verifies Chainlink Data Streams v10 signed reports on-chain via the `IVerifierProxy`. Used for price feed verification during observations.

- Verifies signed report → caches price per feedId
- Max staleness: 3,600 seconds
- Allowlist of accepted feed IDs
- Returns `int192 price` normalized to 8 decimals

## Pyth Network

**Contract**: `PythAdapter`

Pull-based oracle adapter. Callers provide VAA data to update prices before reading.

- Normalizes Pyth's variable exponent to 8 decimals
- Per-asset feed ID mapping
- Configurable max price age (default 24h)
- Used as primary price source on Ink Sepolia testnet

## 1inch Aggregation

**Contract**: `OneInchSwapper`

DEX aggregation with automatic retry:

- **Attempt 1**: 0.5% slippage
- **Attempt 2**: 1.0% slippage
- **Attempt 3**: 1.5% slippage
- Reverts `SwapFailed(3)` if all attempts fail

Used for spot xStock purchases (hedge open) and sales (hedge close).

## Nado (Perp DEX)

**Contract**: `NadoAdapter`

Equity perpetual futures on Ink. Used for the short leg of the delta-neutral hedge.

- `openShort(pairIndex, notional, leverage)` — opens a 1x short position
- `closeShort(positionId)` — closes position, returns PnL
- `claimFunding(positionId)` — claims accumulated funding payments
- `getPosition(positionId)` — reads PnL, margin, size, funding

Funding rate on shorts is the primary carry source (~55% of total carry).

## Tydro (Aave V3 Fork on Ink)

**Contract**: `TydroAdapter`

Lending and collateral operations:

- **Deposit collateral**: xStocks deposited as collateral for borrowing
- **Borrow USDC**: borrowed against collateral for perp margin
- **USDC lending**: idle USDC earns lending yield
- **Rate conversion**: Tydro uses ray (1e27) per-second rates, adapter normalizes to bps

Deployed on Ink mainnet at `0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA`.

## Euler V2

**Contract**: `EulerAdapter`

ERC-4626 vault adapter for reserve fund yield:

- Deposits idle USDC into Euler V2 vault
- Yield accrues automatically via share appreciation
- Used exclusively by `ReserveFund` for reserve yield
- Asset mismatch validation at deployment

## Coupon Streaming (Sablier-style)

**Contract**: `CouponStreamer` (SablierStream.sol)

Self-contained linear coupon streaming (Sablier V2 is not deployed on Ink):

- Creates linear vesting streams from `startTime` to `endTime`
- Max 12 streams per note (6 observations + buffer)
- Holders call `withdraw(streamId)` to claim vested USDC
- On settlement, unvested amounts are refunded to the protocol

```
Vesting formula: vested = deposit * elapsed / duration
```

## Testnet Swap

**Contract**: `TestnetSwap`

Fixed-price swap for Ink Sepolia where real DEXes are unavailable:

- Owner sets per-token prices (e.g., NVDAx = $130)
- Provides USDC ↔ xStock swaps at configured rates
- Owner funds liquidity pool manually
- Not used in production — replaced by OneInchSwapper
