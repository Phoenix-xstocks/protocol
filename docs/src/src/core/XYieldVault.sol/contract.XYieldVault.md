# XYieldVault
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/core/XYieldVault.sol)

**Inherits:**
[IXYieldVault](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IXYieldVault.sol/interface.IXYieldVault.md), AccessControl, ReentrancyGuard

ERC-7540 async vault for Phoenix Autocall deposits.
requestDeposit -> pricing -> hedge -> claimDeposit -> NoteToken minted.
24h max delay, auto-refund if not claimed in time.


## State Variables
### OPERATOR_ROLE

```solidity
bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
```


### MIN_NOTE_SIZE

```solidity
uint256 public constant MIN_NOTE_SIZE = 100e6;
```


### MAX_NOTE_SIZE

```solidity
uint256 public constant MAX_NOTE_SIZE = 100_000e6;
```


### MAX_TVL

```solidity
uint256 public constant MAX_TVL = 5_000_000e6;
```


### MAX_ACTIVE_NOTES

```solidity
uint256 public constant MAX_ACTIVE_NOTES = 500;
```


### CLAIM_DEADLINE

```solidity
uint256 public constant CLAIM_DEADLINE = 24 hours;
```


### usdc

```solidity
IERC20 public immutable usdc;
```


### engine

```solidity
IAutocallEngine public immutable engine;
```


### noteToken

```solidity
NoteToken public immutable noteToken;
```


### feeCollector

```solidity
IFeeCollector public feeCollector;
```


### requests

```solidity
mapping(uint256 => DepositRequest) public requests;
```


### nextRequestId

```solidity
uint256 public nextRequestId;
```


### activeNoteCount

```solidity
uint256 public activeNoteCount;
```


### _totalAssets

```solidity
uint256 private _totalAssets;
```


## Functions
### constructor


```solidity
constructor(address admin, address _usdc, address _engine, address _noteToken);
```

### setFeeCollector

Set the fee collector. Admin only.


```solidity
function setFeeCollector(address _feeCollector) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### requestDeposit


```solidity
function requestDeposit(uint256 amount, address receiver) external override nonReentrant returns (uint256 requestId);
```

### requestDepositWithBasket

Request deposit with basket preference. User chooses their xStocks.


```solidity
function requestDepositWithBasket(uint256 amount, address receiver, address[] calldata basket)
    external
    nonReentrant
    returns (uint256 requestId);
```

### _requestDeposit


```solidity
function _requestDeposit(uint256 amount, address receiver, address[] memory basket)
    internal
    returns (uint256 requestId);
```

### fulfillDeposit

Operator marks request as ready after pricing + hedge opened


```solidity
function fulfillDeposit(uint256 requestId, bytes32 noteId, address[] calldata basket)
    external
    onlyRole(OPERATOR_ROLE);
```

### claimDeposit


```solidity
function claimDeposit(uint256 requestId) external override nonReentrant returns (uint256 noteTokenId);
```

### refundDeposit

Auto-refund if claim deadline passed


```solidity
function refundDeposit(uint256 requestId) external nonReentrant;
```

### requestRedeem


```solidity
function requestRedeem(uint256) external pure override returns (uint256);
```

### claimRedeem


```solidity
function claimRedeem(uint256) external pure override returns (uint256);
```

### noteSettled

Called by engine/operator when a note settles to update accounting


```solidity
function noteSettled(uint256 amount) external onlyRole(OPERATOR_ROLE);
```

### totalAssets


```solidity
function totalAssets() external view override returns (uint256);
```

### maxDeposit


```solidity
function maxDeposit(address) external view override returns (uint256);
```

## Events
### DepositRequested

```solidity
event DepositRequested(uint256 indexed requestId, address indexed depositor, uint256 amount);
```

### DepositReadyToClaim

```solidity
event DepositReadyToClaim(uint256 indexed requestId, bytes32 indexed noteId);
```

### DepositClaimed

```solidity
event DepositClaimed(uint256 indexed requestId, bytes32 indexed noteId, uint256 tokenId);
```

### DepositRefunded

```solidity
event DepositRefunded(uint256 indexed requestId, address indexed depositor, uint256 amount);
```

## Errors
### BelowMinDeposit

```solidity
error BelowMinDeposit();
```

### AboveMaxDeposit

```solidity
error AboveMaxDeposit();
```

### TVLExceeded

```solidity
error TVLExceeded();
```

### MaxNotesExceeded

```solidity
error MaxNotesExceeded();
```

### InvalidRequestStatus

```solidity
error InvalidRequestStatus();
```

### NotReceiver

```solidity
error NotReceiver();
```

### ClaimDeadlineNotReached

```solidity
error ClaimDeadlineNotReached();
```

### ClaimDeadlinePassed

```solidity
error ClaimDeadlinePassed();
```

### ZeroAmount

```solidity
error ZeroAmount();
```

## Structs
### DepositRequest

```solidity
struct DepositRequest {
    address depositor;
    address receiver;
    uint256 amount;
    address[] basket;
    bytes32 noteId;
    uint256 requestedAt;
    uint256 readyAt;
    RequestStatus status;
}
```

## Enums
### RequestStatus

```solidity
enum RequestStatus {
    Pending,
    ReadyToClaim,
    Claimed,
    Refunded,
    Cancelled
}
```

