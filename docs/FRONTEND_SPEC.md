# xYield Protocol - Frontend Integration Spec

## Contract Addresses (Ink Sepolia)

| Contract | Address |
|---|---|
| AutocallEngine | `0xe6bf9838b13956f9ff8bde0008d7b333f82293b7` |
| XYieldVault | `0xd4a1d2ffd7e12cdf44fdd20cbbd398cbd6320e32` |
| NoteToken | `0xb72654ed175dfd49146ae163d494b4339f445482` |
| CouponStreamer | `0xe220e9de9086f823b39cc5271912f0c17e7aeb80` |
| ProtocolStats | `0x4075d5a6725f3710031984970e4b44670a0acaae` |
| USDC | `0x6b57475467cd854d36Be7FB614caDa5207838943` |
| wQQQx (NASDAQ) | `0x267ED9BC43B16D832cB9Aaf0e3445f0cC9f536d9` |
| wSPYx (SPX) | `0x9eF9f9B22d3CA9769e28e769e2AAA3C2B0072D0e` |

---

## 1. User Flow: Deposit to Active Note

### Step 1 - Deposit (User tx)

```
USDC.approve(XYieldVault, amount)
XYieldVault.requestDeposit(amount, receiverAddress) -> requestId
```

- **Min:** 100 USDC, **Max:** 100,000 USDC
- Emits `DepositRequested(requestId, depositor, amount)`
- USDC is transferred to the vault immediately

### Step 2 - Wait for Pricing (Backend/Keeper)

The keeper (backend) fulfills the deposit after CRE pricing completes:

```
XYieldVault.fulfillDeposit(requestId, noteId, basket)  // OPERATOR_ROLE
```

- Emits `DepositReadyToClaim(requestId, noteId)`
- Frontend should poll `getState(noteId)` or listen for this event

### Step 3 - Claim (User tx)

```
XYieldVault.claimDeposit(requestId) -> noteTokenId
```

- Must be called by the `receiver` address
- Must claim within **24 hours** of fulfillment (auto-refundable after)
- Deducts **0.6% fees** (0.5% embedded + 0.1% origination)
- Mints soulbound ERC-1155 NoteToken to user
- Transfers net USDC to AutocallEngine
- Emits `DepositClaimed(requestId, noteId, tokenId)`

### Step 4 - Refund (if unclaimed)

If the user doesn't claim within 24h, anyone can trigger a refund:

```
XYieldVault.refundDeposit(requestId)
```

- Returns original USDC to depositor

---

## 2. Note Lifecycle (Keeper/Backend operations)

After claim, the note goes through this state machine:

```
Created -> Priced -> Active -> [observations] -> Settled
```

### Pricing (Keeper)

```
// CRE path (production):
AutocallEngine.priceNote(noteId, initialPrices)

// Direct path (testnet):
AutocallEngine.priceNoteDirect(noteId, initialPrices, putPremiumBps)
```

- `initialPrices`: spot prices at note creation (int256[], one per basket token, 8 decimals)
- Reads CRE pricing result from CREConsumer
- Computes coupon rate from vol + carry + premium
- Transitions Created -> Priced

### Activation (Keeper)

```
AutocallEngine.activateNote(noteId)
```

- Runs issuance gate checks (CRE pricing accepted, reserve funded, TVL limits)
- Opens delta-neutral hedge (spot buy + Tydro collateral + USDC borrow)
- Transitions Priced -> Active

### Observations (Keeper, every 30 days)

```
AutocallEngine.observe(noteId)
```

- **Anyone can call** (typically keeper, but open)
- Minimum 30-day interval between observations
- 6 observations total over 180-day maturity
- At each observation, evaluates worst-of performance across basket

**Outcomes per observation:**

| Worst-of Performance | Result |
|---|---|
| >= autocall trigger | **Autocalled** - note settles early, all coupons paid |
| >= 70% (coupon barrier) | **Coupon paid** via streaming + memory coupons cleared |
| < 70% | **Coupon missed** - base coupon accumulates as "memory" |

**Autocall trigger steps down 2% per observation:**
- Obs 1: 100%, Obs 2: 98%, Obs 3: 96%, Obs 4: 94%, Obs 5: 92%, Obs 6: 90%

### Maturity (after 6th observation)

If not autocalled, the note reaches maturity:

| Final Worst-of Performance | Result |
|---|---|
| >= 70% (KI barrier) | **No KI** - principal returned in full + final coupon |
| < 70% | **KI breach** - holder chooses settlement method |

### KI Settlement (User tx, 7-day window)

If knock-in barrier is breached:

```
AutocallEngine.settleKi(noteId, preferPhysical)
```

- `preferPhysical = true`: liquidate hedge shares, get full recovery amount
- `preferPhysical = false`: cash settlement at `notional * worstPerformance`
- **Must be called within 7 days** by note holder
- After 7 days, admin can force-settle via `forceSettleKi(noteId)` (defaults to cash)

---

## 3. Coupon Streaming (Sablier-like)

When a coupon is paid at an observation, it's delivered via **linear streaming** over the next 30-day period.

### How it works

1. At observation, if coupon barrier (70%) is hit, the engine calls:
   ```
   CouponStreamer.startCouponStream(noteId, holder, amount, startTime, endTime)
   ```
2. USDC is locked in the CouponStreamer contract
3. It vests **linearly** from startTime to endTime (30 days)
4. Holder withdraws vested amount at any time

### Withdraw vested coupons (User tx)

```
// Check how much is withdrawable
CouponStreamer.getWithdrawable(streamId) -> uint256

// Withdraw
CouponStreamer.withdraw(streamId)
```

- Only the stream recipient can withdraw
- Can call multiple times as more vests
- Emits `CouponWithdrawn(streamId, recipient, amount)`

### Frontend: display streaming info

```
// Get all stream IDs for a note
CouponStreamer.getNoteStreams(noteId) -> uint256[]

// For each stream, get details
CouponStreamer.getStream(streamId) -> (recipient, deposit, startTime, endTime, withdrawn, canceled)

// Calculate real-time withdrawable
CouponStreamer.getWithdrawable(streamId) -> uint256
```

**UI should show:**
- Total coupon amount (deposit)
- Already withdrawn
- Currently withdrawable (update in real-time with a timer)
- Stream progress bar (elapsed / duration)

### Cancellation on settlement

When a note is settled (autocall, maturity, or KI), all active streams are cancelled:
- Vested but unclaimed amounts are transferred to the holder
- Unvested amounts are refunded to the engine
- Max 12 streams per note (6 observations + margin)

---

## 4. Reading Protocol State

### Single note status

```
AutocallEngine.getState(noteId) -> State (uint8)
```

States: 0=Created, 1=Priced, 2=Active, 3=ObservationPending, 4=Autocalled, 5=MaturityCheck, 6=NoKISettle, 7=KISettle, 8=Settled, 9=Cancelled, 10=EmergencyPaused

### Full note details

```
AutocallEngine.getNote(noteId) -> (basket, notional, holder, state, observations, memoryCoupon, totalCouponBps, createdAt, maturityDate)
```

### Note status snapshot (frontend-friendly)

```
AutocallEngine.getNoteStatus(noteId) -> (state, observations, nextObservationTime, currentTriggerBps, couponPerObsBps)
```

### Dashboard metrics (single call)

```
ProtocolStats.getStats(totalNotional) -> Stats
```

Returns: totalNotesCreated, tvl, maxDeposit, reserveBalance, engineUsdcBalance, vaultUsdcBalance, reserveLevel

### User's notes

NoteToken is ERC-1155. To find a user's notes:
- Listen for `NoteMinted(noteId, holder, amount)` events filtered by holder
- Or use `NoteToken.balanceOf(userAddress, uint256(noteId))` if you know the noteId

---

## 5. Events to Subscribe To

### For deposit tracking

```
XYieldVault.DepositRequested(requestId, depositor, amount)
XYieldVault.DepositReadyToClaim(requestId, noteId)
XYieldVault.DepositClaimed(requestId, noteId, tokenId)
XYieldVault.DepositRefunded(requestId, depositor, amount)
```

### For note lifecycle

```
AutocallEngine.NoteCreated(noteId, holder, notional)
AutocallEngine.NoteStateChanged(noteId, fromState, toState)
AutocallEngine.CouponPaid(noteId, amount, memoryPaid)
AutocallEngine.CouponMissed(noteId, memoryAccumulated)
AutocallEngine.CouponStreamed(noteId, streamId, amount)
AutocallEngine.NoteAutocalled(noteId, observations)
AutocallEngine.NoteSettled(noteId, payout, kiPhysical)
```

### For coupon streaming

```
CouponStreamer.CouponStreamStarted(noteId, holder, streamId, amount)
CouponStreamer.CouponWithdrawn(streamId, recipient, amount)
CouponStreamer.CouponStreamCancelled(noteId, streamId, refundedAmount)
```

---

## 6. Chainlink CRE Integration

### Two workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| **Vol Oracle** | Cron (every 2h) | Fetches QQQ/SPY realized vols + correlation from Twelve Data, writes to VolOracle on-chain |
| **Pricing** | Event (`RequestPricing`) | Reads note params + vols, runs 10k-path Monte Carlo, delivers PricingResult to CREConsumer |

### How to run (simulation mode)

CRE workflows cannot be deployed to production DON yet. They run via `cre workflow simulate --broadcast`:

#### Vol Oracle (run periodically or before pricing)

```bash
cd phoenix-cre
cre workflow simulate vol-oracle-workflow --target production-settings --broadcast
```

- Fetches daily returns from Twelve Data API for QQQ and SPY
- Computes annualized realized vol (std * sqrt(252)) and Pearson correlation
- Encodes and submits report to VolOracle via KeystoneForwarder
- **Schedule:** Run every 2 hours, or at minimum before any note pricing

#### Pricing (run after each createNote)

```bash
cd phoenix-cre
cre workflow simulate pricing-workflow \
  --target production-settings \
  --broadcast \
  --non-interactive \
  --trigger-index 0 \
  --evm-event-index 2 \
  --evm-tx-hash <createNote_tx_hash>
```

- Reads note params from CREConsumer
- Reads vols/correlations from VolOracle
- Fetches spot prices from Pyth
- Runs Monte Carlo (10k paths, deterministic RNG)
- Outputs: putPremiumBps, kiProbabilityBps, expectedKILossBps, vegaBps
- Submits signed report to CREConsumer

### Manual fallback (if CRE simulation unavailable)

Since the CRE simulate `--broadcast` doesn't actually write reports on-chain (it goes through a simulated forwarder), the current approach for delivering pricing is:

1. Set deployer as forwarder: `CREConsumer.setForwarder(deployerAddress)`
2. Encode and call `CREConsumer.onReport(metadata, report)` directly
3. The report is ABI-encoded as: `(bytes32 noteId, (uint16 putPremiumBps, uint16 kiProbabilityBps, uint16 expectedKILossBps, uint16 vegaBps, bytes32 inputsHash))`

The on-chain OptionPricer cross-checks the MC premium against an analytical approximation (tolerance: 500bps).

### Production CRE flow (when DON access is granted)

Once deployed to the DON:

1. **Vol Oracle** runs on cron schedule automatically (every 2h)
2. **Pricing** is event-driven - the DON listens for `RequestPricing` events from AutocallEngine and triggers automatically
3. No manual intervention needed - the full flow becomes:
   - User deposits -> createNote emits RequestPricing
   - CRE DON picks up event -> runs MC -> delivers pricing
   - Keeper calls priceNote (reads from CREConsumer) -> activateNote

### Keeper responsibilities summary

| Action | Trigger | Method |
|---|---|---|
| Fulfill deposit | After CRE pricing delivered | `vault.fulfillDeposit()` |
| Price note | After CRE pricing accepted | `engine.priceNote()` |
| Activate note | After pricing | `engine.activateNote()` |
| Observe | Every 30 days per active note | `engine.observe()` |
| Force settle KI | 7 days after KI breach | `engine.forceSettleKi()` |
| Update vols | Every 2h (CRE or manual) | `volOracle.updateVols()` |

---

## 7. Key Parameters

| Parameter | Value | Location |
|---|---|---|
| Min deposit | 100 USDC | XYieldVault |
| Max deposit | 100,000 USDC | XYieldVault |
| Max TVL | 5,000,000 USDC | XYieldVault |
| Max active notes | 500 | XYieldVault |
| Claim deadline | 24 hours | XYieldVault |
| Embedded fee | 0.5% | XYieldVault |
| Origination fee | 0.1% | XYieldVault |
| Maturity | 180 days | AutocallEngine |
| Observations | 6 (every 30 days) | AutocallEngine |
| Coupon barrier | 70% | AutocallEngine |
| KI barrier | 70% (European) | AutocallEngine |
| Autocall trigger | 100% (steps down 2%/obs) | AutocallEngine |
| KI settlement window | 7 days | AutocallEngine |
| Price staleness | 24 hours max | AutocallEngine |
| Reserve minimum | 3% of notional | IssuanceGate |
| Max streams per note | 12 | CouponStreamer |
