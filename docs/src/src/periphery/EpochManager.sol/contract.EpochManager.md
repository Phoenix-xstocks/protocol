# EpochManager
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/periphery/EpochManager.sol)

**Inherits:**
[IEpochManager](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IEpochManager.sol/interface.IEpochManager.md), Ownable, ReentrancyGuard

48h epoch cycles. NAV calculation, waterfall distribution (P1-P6),
rebalance trigger.
Waterfall priority (strict order, NEVER skip):
P1 (SENIOR): Base coupons due -- ALWAYS paid first
P2 (SENIOR): Principal repayment
P3 (MEZZ):   Carry enhancement retail
P4 (JUNIOR): Hedge operational costs
P5 (JUNIOR): Reserve fund contribution
P6 (EQUITY): Protocol treasury
NEVER P6 if P1 unpaid


## State Variables
### BPS

```solidity
uint256 public constant BPS = 10000;
```


### EPOCH_DURATION

```solidity
uint256 public constant EPOCH_DURATION = 48 hours;
```


### RESERVE_CONTRIBUTION_BPS

```solidity
uint256 public constant RESERVE_CONTRIBUTION_BPS = 3000;
```


### usdc

```solidity
IERC20 public usdc;
```


### reserveFund

```solidity
IReserveFund public reserveFund;
```


### feeCollector

```solidity
IFeeCollector public feeCollector;
```


### carryEngine

```solidity
ICarryEngine public carryEngine;
```


### hedgeManager

```solidity
IHedgeManager public hedgeManager;
```


### treasury
Treasury receives P6 equity residual


```solidity
address public treasury;
```


### couponRecipient
Coupon recipient receives P1/P3 funds (e.g. AutocallEngine)


```solidity
address public couponRecipient;
```


### currentEpoch

```solidity
uint256 public currentEpoch;
```


### epochStartTimestamp

```solidity
uint256 public epochStartTimestamp;
```


### totalNotionalOutstanding

```solidity
uint256 public totalNotionalOutstanding;
```


### activeNoteIds
Active note IDs for rebalancing


```solidity
bytes32[] public activeNoteIds;
```


### pendingAmounts
Configurable waterfall amounts (set by owner before distribution)


```solidity
WaterfallAmounts public pendingAmounts;
```


### lastResult
Last distribution result


```solidity
WaterfallResult public lastResult;
```


## Functions
### constructor


```solidity
constructor(
    address _usdc,
    address _reserveFund,
    address _feeCollector,
    address _carryEngine,
    address _hedgeManager,
    address _treasury,
    address _couponRecipient,
    address _owner
) Ownable(_owner);
```

### addNote

Register an active note for epoch processing


```solidity
function addNote(bytes32 noteId, uint256 notional) external onlyOwner;
```

### removeNote

Remove a settled note


```solidity
function removeNote(uint256 index, uint256 notional) external onlyOwner;
```

### setPendingAmounts

Set waterfall amounts for next distribution


```solidity
function setPendingAmounts(
    uint256 baseCouponsDue,
    uint256 principalDue,
    uint256 carryEnhancementDue,
    uint256 hedgeCostsDue
) external onlyOwner;
```

### getCurrentEpoch


```solidity
function getCurrentEpoch() external view returns (uint256);
```

### getEpochStart


```solidity
function getEpochStart(uint256 epochId) external view returns (uint256 timestamp);
```

### isEpochReady


```solidity
function isEpochReady() public view returns (bool);
```

### advanceEpoch


```solidity
function advanceEpoch() external onlyOwner;
```

### distributeWaterfall

Distributes available cash according to P1-P6 waterfall.
Cash source: USDC balance of this contract.
INVARIANT: P6 is NEVER paid if P1 is not fully covered.


```solidity
function distributeWaterfall() external onlyOwner nonReentrant;
```

### triggerRebalances

Trigger rebalance for all active notes


```solidity
function triggerRebalances() external;
```

### getLastResult

Get last waterfall distribution result


```solidity
function getLastResult() external view returns (WaterfallResult memory);
```

### getActiveNoteCount

Get count of active notes


```solidity
function getActiveNoteCount() external view returns (uint256);
```

### _min


```solidity
function _min(uint256 a, uint256 b) internal pure returns (uint256);
```

### _abs


```solidity
function _abs(int256 x) internal pure returns (uint256);
```

## Events
### EpochAdvanced

```solidity
event EpochAdvanced(uint256 indexed epochId, uint256 timestamp);
```

### WaterfallDistributed

```solidity
event WaterfallDistributed(
    uint256 indexed epochId,
    uint256 p1Paid,
    uint256 p2Paid,
    uint256 p3Paid,
    uint256 p4Paid,
    uint256 p5Paid,
    uint256 p6Paid
);
```

### RebalanceTriggered

```solidity
event RebalanceTriggered(uint256 indexed epochId, bytes32 noteId);
```

### NoteAdded

```solidity
event NoteAdded(bytes32 indexed noteId);
```

### NoteRemoved

```solidity
event NoteRemoved(bytes32 indexed noteId);
```

## Structs
### WaterfallAmounts
Amounts due for waterfall distribution


```solidity
struct WaterfallAmounts {
    uint256 baseCouponsDue;
    uint256 principalDue;
    uint256 carryEnhancementDue;
    uint256 hedgeCostsDue;
}
```

### WaterfallResult
Result of waterfall distribution


```solidity
struct WaterfallResult {
    uint256 p1Paid;
    uint256 p2Paid;
    uint256 p3Paid;
    uint256 p4Paid;
    uint256 p5Paid;
    uint256 p6Paid;
    bool p1FullyPaid;
}
```

