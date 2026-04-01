# AutocallEngine
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/core/AutocallEngine.sol)

**Inherits:**
[IAutocallEngine](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IAutocallEngine.sol/interface.IAutocallEngine.md), AccessControl, ReentrancyGuard

State machine with 12 states for Phoenix Autocall worst-of notes.
Handles create, observe (autocall/coupon/KI), and settle flows.


## State Variables
### KEEPER_ROLE

```solidity
bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
```


### VAULT_ROLE

```solidity
bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
```


### BPS

```solidity
uint256 public constant BPS = 10_000;
```


### MAX_OBSERVATIONS

```solidity
uint256 public constant MAX_OBSERVATIONS = 6;
```


### OBS_INTERVAL_DAYS

```solidity
uint256 public constant OBS_INTERVAL_DAYS = 30;
```


### COUPON_BARRIER_BPS

```solidity
uint16 public constant COUPON_BARRIER_BPS = 7_000;
```


### AUTOCALL_TRIGGER_BPS

```solidity
uint16 public constant AUTOCALL_TRIGGER_BPS = 10_000;
```


### STEP_DOWN_BPS

```solidity
uint16 public constant STEP_DOWN_BPS = 200;
```


### KI_BARRIER_BPS

```solidity
uint16 public constant KI_BARRIER_BPS = 7_000;
```


### MATURITY_DAYS

```solidity
uint256 public constant MATURITY_DAYS = 180;
```


### PRICE_MAX_STALENESS

```solidity
uint256 public constant PRICE_MAX_STALENESS = 24 hours;
```


### KI_SETTLE_DEADLINE

```solidity
uint256 public constant KI_SETTLE_DEADLINE = 7 days;
```


### _notes

```solidity
mapping(bytes32 => Note) internal _notes;
```


### noteCount

```solidity
uint256 public noteCount;
```


### noteIds

```solidity
bytes32[] public noteIds;
```


### usdc

```solidity
IERC20 public immutable usdc;
```


### hedgeManager

```solidity
IHedgeManager public immutable hedgeManager;
```


### creConsumer

```solidity
ICREConsumer public immutable creConsumer;
```


### issuanceGate

```solidity
IIssuanceGate public immutable issuanceGate;
```


### couponCalculator

```solidity
ICouponCalculator public immutable couponCalculator;
```


### priceFeed

```solidity
IPriceFeed public immutable priceFeed;
```


### volOracle

```solidity
IVolOracle public immutable volOracle;
```


### carryEngine

```solidity
ICarryEngine public immutable carryEngine;
```


### noteToken

```solidity
NoteToken public immutable noteToken;
```


### sablierStream
Sablier coupon streaming adapter (set post-deploy, optional)


```solidity
ISablierStream public sablierStream;
```


### feedIds
Maps xStock token address -> Pyth/Chainlink feed ID


```solidity
mapping(address => bytes32) public feedIds;
```


### testnetMode
Testnet mode: skip issuance gate CRE check


```solidity
bool public testnetMode;
```


## Functions
### setTestnetMode


```solidity
function setTestnetMode(bool _testnet) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### setSablierStream

Set the Sablier coupon streaming adapter. Admin only.


```solidity
function setSablierStream(address _sablierStream) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### constructor


```solidity
constructor(
    address admin,
    address _usdc,
    address _hedgeManager,
    address _creConsumer,
    address _issuanceGate,
    address _couponCalculator,
    address _priceFeed,
    address _volOracle,
    address _carryEngine,
    address _noteToken
);
```

### setFeedId

Set the Chainlink feed ID for an xStock token. Admin only.


```solidity
function setFeedId(address xStock, bytes32 feedId) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### setFeedIds

Batch-set feed IDs for multiple xStocks.


```solidity
function setFeedIds(address[] calldata xStocks, bytes32[] calldata _feedIds) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### createNote


```solidity
function createNote(address[] calldata basket, uint256 notional, address holder)
    external
    override
    onlyRole(VAULT_ROLE)
    returns (bytes32 noteId);
```

### priceNote

Called after CRE pricing is accepted. Transitions CREATED -> PRICED.
Reads actual vol from VolOracle and carry rate from CarryEngine
to compute dynamic safety margin and carry enhancement per spec section 5.


```solidity
function priceNote(bytes32 noteId, int256[] calldata initialPrices) external onlyRole(KEEPER_ROLE);
```

### priceNoteDirect

Direct pricing for testnet — keeper provides premium directly.
Bypasses CRE for testing. In production, use priceNote() with CRE.


```solidity
function priceNoteDirect(bytes32 noteId, int256[] calldata initialPrices, uint256 putPremiumBps)
    external
    onlyRole(KEEPER_ROLE);
```

### activateNote

Transitions PRICED -> ACTIVE after issuance gate approval (INV-6).
Opens the delta-neutral hedge (spot + perps) per spec section 10.


```solidity
function activateNote(bytes32 noteId) external onlyRole(KEEPER_ROLE);
```

### observe


```solidity
function observe(bytes32 noteId) external override nonReentrant;
```

### settleKI


```solidity
function settleKI(bytes32 noteId, bool preferPhysical) external override nonReentrant;
```

### forceSettleKI

Admin force-settle KI if holder doesn't choose within deadline.
Defaults to cash settlement to protect the holder.


```solidity
function forceSettleKI(bytes32 noteId) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant;
```

### emergencyPause


```solidity
function emergencyPause(bytes32 noteId) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### emergencyResume


```solidity
function emergencyResume(bytes32 noteId) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### cancelNote


```solidity
function cancelNote(bytes32 noteId) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### getState


```solidity
function getState(bytes32 noteId) external view override returns (State);
```

### getNoteCount


```solidity
function getNoteCount() external view override returns (uint256);
```

### getNote


```solidity
function getNote(bytes32 noteId)
    external
    view
    returns (
        address[] memory basket,
        uint256 notional,
        address holder,
        State state,
        uint8 observations,
        uint256 memoryCoupon,
        uint256 totalCouponBps,
        uint256 createdAt,
        uint256 maturityDate
    );
```

### getNoteStatus

Get computed status for frontend display


```solidity
function getNoteStatus(bytes32 noteId)
    external
    view
    returns (
        State state,
        uint8 observations,
        uint256 nextObservationTime,
        uint256 currentTriggerBps,
        uint256 couponPerObsBps
    );
```

### _transition


```solidity
function _transition(bytes32 noteId, State to) internal;
```

### _requireState


```solidity
function _requireState(bytes32 noteId, State expected) internal view;
```

### _isValidTransition

*INV-4: only allowed transitions*


```solidity
function _isValidTransition(State from, State to) internal pure returns (bool);
```

### _getWorstPerformance

Calculate the worst-of performance across the basket.
perf_i = currentPrice_i / initialPrice_i * BPS
Returns min(perf_i) in basis points.


```solidity
function _getWorstPerformance(Note storage note) internal view returns (uint256);
```

### _payCoupon


```solidity
function _payCoupon(bytes32 noteId, Note storage note, bool includeMemory) internal;
```

### _cancelAllNoteStreams

Cancel all active Sablier streams for a note on settlement.
Refunded USDC stays in SablierStream and can be recovered by admin.


```solidity
function _cancelAllNoteStreams(bytes32 noteId) internal;
```

### _settleAutocall


```solidity
function _settleAutocall(bytes32 noteId, Note storage note) internal;
```

### _handleMaturity


```solidity
function _handleMaturity(bytes32 noteId, Note storage note, uint256 worstPerfBps) internal;
```

### _settleNoKI


```solidity
function _settleNoKI(bytes32 noteId, Note storage note) internal;
```

### _burnNoteToken

Burn NoteToken + update issuance gate on settlement.


```solidity
function _burnNoteToken(bytes32 noteId, Note storage note) internal;
```

## Events
### NoteCreated

```solidity
event NoteCreated(bytes32 indexed noteId, address indexed holder, uint256 notional);
```

### RequestPricing

```solidity
event RequestPricing(bytes32 indexed noteId, address[] basket, uint256 notional);
```

### NoteStateChanged

```solidity
event NoteStateChanged(bytes32 indexed noteId, State from, State to);
```

### CouponPaid

```solidity
event CouponPaid(bytes32 indexed noteId, uint256 amount, uint256 memoryPaid);
```

### CouponMissed

```solidity
event CouponMissed(bytes32 indexed noteId, uint256 memoryAccumulated);
```

### CouponStreamed

```solidity
event CouponStreamed(bytes32 indexed noteId, uint256 streamId, uint256 amount);
```

### NoteAutocalled

```solidity
event NoteAutocalled(bytes32 indexed noteId, uint8 observation);
```

### NoteSettled

```solidity
event NoteSettled(bytes32 indexed noteId, uint256 payout, bool kiPhysical);
```

### EmergencyPaused

```solidity
event EmergencyPaused(bytes32 indexed noteId);
```

### EmergencyResumed

```solidity
event EmergencyResumed(bytes32 indexed noteId);
```

### NoteCancelled

```solidity
event NoteCancelled(bytes32 indexed noteId);
```

## Errors
### InvalidState

```solidity
error InvalidState(State current, State expected);
```

### InvalidTransition

```solidity
error InvalidTransition(State from, State to);
```

### OnlyHolder

```solidity
error OnlyHolder();
```

### InvalidBasket

```solidity
error InvalidBasket();
```

### IssuanceNotApproved

```solidity
error IssuanceNotApproved(string reason);
```

### NoteNotFound

```solidity
error NoteNotFound();
```

### ObservationTooEarly

```solidity
error ObservationTooEarly(uint256 earliest, uint256 current);
```

### StalePriceFeed

```solidity
error StalePriceFeed(bytes32 feedId, uint32 feedTimestamp);
```

## Structs
### Note

```solidity
struct Note {
    address[] basket;
    uint256 notional;
    address holder;
    State state;
    uint8 observations;
    uint256 memoryCoupon;
    uint256 totalCouponBps;
    uint256 baseCouponBps;
    uint256 createdAt;
    uint256 maturityDate;
    uint256 lastObservationTime;
    uint256 kiSettleStartTime;
    int256[] initialPrices;
}
```

