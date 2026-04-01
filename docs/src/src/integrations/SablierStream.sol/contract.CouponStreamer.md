# CouponStreamer
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/SablierStream.sol)

**Inherits:**
[ISablierStream](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/ISablierStream.sol/interface.ISablierStream.md), Ownable, ReentrancyGuard

Self-contained linear token streaming for coupon payments.
Replaces external Sablier V2 (not deployed on Ink). Each stream
linearly vests USDC from startTime to endTime. Holders call withdraw()
to claim; the owner (AutocallEngine) can cancel, returning unvested USDC.


## State Variables
### MAX_STREAMS_PER_NOTE
Max streams per note (6 observations + safety margin)


```solidity
uint256 public constant MAX_STREAMS_PER_NOTE = 12;
```


### usdc

```solidity
IERC20 public immutable usdc;
```


### nextStreamId

```solidity
uint256 public nextStreamId;
```


### streams

```solidity
mapping(uint256 => Stream) public streams;
```


### _noteStreamIds

```solidity
mapping(bytes32 => uint256[]) internal _noteStreamIds;
```


### streamToNote

```solidity
mapping(uint256 => bytes32) public streamToNote;
```


## Functions
### constructor


```solidity
constructor(address _usdc, address _owner) Ownable(_owner);
```

### startCouponStream

*Caller must approve this contract for `monthlyAmount` of USDC before calling.*


```solidity
function startCouponStream(bytes32 noteId, address holder, uint256 monthlyAmount, uint256 startTime, uint256 endTime)
    external
    onlyOwner
    returns (uint256 streamId);
```

### cancelStream


```solidity
function cancelStream(uint256 streamId) external onlyOwner;
```

### cancelAllNoteStreams


```solidity
function cancelAllNoteStreams(bytes32 noteId) external onlyOwner returns (uint256 totalRefunded);
```

### withdraw

Withdraw vested USDC from a stream.


```solidity
function withdraw(uint256 streamId) external nonReentrant;
```

### getStreamedAmount


```solidity
function getStreamedAmount(uint256 streamId) external view returns (uint256);
```

### getNoteStreams


```solidity
function getNoteStreams(bytes32 noteId) external view returns (uint256[] memory);
```

### getStream

Get full stream details.


```solidity
function getStream(uint256 streamId)
    external
    view
    returns (address recipient, uint128 deposit, uint40 startTime, uint40 endTime, uint128 withdrawn, bool canceled);
```

### getWithdrawable

Get the amount a holder can withdraw right now.


```solidity
function getWithdrawable(uint256 streamId) external view returns (uint256);
```

### recoverToken

Recover tokens sent to this contract by mistake.


```solidity
function recoverToken(address token, uint256 amount) external onlyOwner;
```

### _vestedAmount

*Linear vesting: deposit * elapsed / duration, clamped to [0, deposit].*


```solidity
function _vestedAmount(Stream storage s) internal view returns (uint256);
```

## Events
### CouponStreamStarted

```solidity
event CouponStreamStarted(bytes32 indexed noteId, address indexed holder, uint256 streamId, uint256 amount);
```

### CouponStreamCancelled

```solidity
event CouponStreamCancelled(bytes32 indexed noteId, uint256 indexed streamId, uint256 refundedAmount);
```

### CouponWithdrawn

```solidity
event CouponWithdrawn(uint256 indexed streamId, address indexed recipient, uint256 amount);
```

## Errors
### InvalidTimeRange

```solidity
error InvalidTimeRange();
```

### ZeroAmount

```solidity
error ZeroAmount();
```

### StreamNotFound

```solidity
error StreamNotFound(uint256 streamId);
```

### StreamAlreadyCanceled

```solidity
error StreamAlreadyCanceled(uint256 streamId);
```

### NotRecipient

```solidity
error NotRecipient();
```

### NothingToWithdraw

```solidity
error NothingToWithdraw();
```

### TooManyStreams

```solidity
error TooManyStreams(bytes32 noteId);
```

## Structs
### Stream

```solidity
struct Stream {
    address recipient;
    bool canceled;
    uint40 startTime;
    uint40 endTime;
    uint128 deposit;
    uint128 withdrawn;
}
```

