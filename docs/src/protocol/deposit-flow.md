# Deposit Flow

The XYieldVault implements the [ERC-7540](https://eips.ethereum.org/EIPS/eip-7540) asynchronous deposit standard. This separates deposit intent from fulfillment, giving the protocol time to price and hedge before committing capital.

## Flow

```
  User                        Vault                     AutocallEngine
   │                            │                              │
   │── requestDeposit(amt) ────►│                              │
   │                            │── hold USDC                  │
   │                            │── emit DepositRequested      │
   │                            │                              │
   │              [Operator]    │                              │
   │                            │── fulfillDeposit() ─────────►│
   │                            │                      createNote()
   │                            │                      registerParams()
   │                            │◄─── noteId ──────────────────│
   │                            │── status = ReadyToClaim      │
   │                            │                              │
   │              [CRE prices the note asynchronously]         │
   │                            │                              │
   │── claimDeposit(reqId) ────►│                              │
   │                            │── deduct fees (0.6%)         │
   │                            │── mint NoteToken             │
   │                            │── transfer USDC to engine    │
   │◄── NoteToken minted ──────│                              │
```

## Step 1: Request Deposit

```solidity
function requestDeposit(uint256 amount, address receiver) external
```

- User approves USDC and calls `requestDeposit`
- Optionally use `requestDepositWithBasket(amount, receiver, basket)` to specify preferred xStocks
- USDC is transferred to the vault and held
- A `DepositRequest` is created with status `Pending`
- Emits `DepositRequested(requestId, depositor, amount)`

**Limits:**
- Minimum: $100 USDC
- Maximum: $100,000 USDC
- TVL cap: $5,000,000

## Step 2: Fulfill Deposit (Operator)

```solidity
function fulfillDeposit(uint256 requestId, bytes32 noteId, address[] basket) external
```

- The operator selects a basket (or uses the one the user requested)
- Creates a note on AutocallEngine
- Registers pricing parameters with CREConsumer
- Sets the request status to `ReadyToClaim`
- CRE pricing and note activation happen asynchronously

## Step 3: Claim Deposit

```solidity
function claimDeposit(uint256 requestId) external
```

- Must be called within **24 hours** of fulfillment
- Fees are deducted:
  - Embedded fee: **0.5%**
  - Origination fee: **0.1%**
  - Net amount = deposit - 0.6%
- NoteToken (ERC-1155) is minted for the net amount
- Net USDC is transferred to AutocallEngine
- If not claimed within 24h, a refund can be triggered

## Redemption

There is no vault-level redemption. Notes are redeemed through the AutocallEngine settlement flow:

```solidity
function requestRedeem() → reverts with "Redeem via AutocallEngine.settleKI"
```

This is intentional — structured product redemption follows the note lifecycle, not a vault withdraw.
