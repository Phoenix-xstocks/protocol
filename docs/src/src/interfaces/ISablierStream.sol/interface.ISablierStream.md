# ISablierStream
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/ISablierStream.sol)


## Functions
### startCouponStream


```solidity
function startCouponStream(bytes32 noteId, address holder, uint256 monthlyAmount, uint256 startTime, uint256 endTime)
    external
    returns (uint256 streamId);
```

### cancelStream


```solidity
function cancelStream(uint256 streamId) external;
```

### cancelAllNoteStreams


```solidity
function cancelAllNoteStreams(bytes32 noteId) external returns (uint256 totalRefunded);
```

### getStreamedAmount


```solidity
function getStreamedAmount(uint256 streamId) external view returns (uint256);
```

### getNoteStreams


```solidity
function getNoteStreams(bytes32 noteId) external view returns (uint256[] memory);
```

