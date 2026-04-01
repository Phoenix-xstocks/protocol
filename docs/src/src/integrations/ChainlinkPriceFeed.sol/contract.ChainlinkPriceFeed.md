# ChainlinkPriceFeed
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/ChainlinkPriceFeed.sol)

**Inherits:**
Ownable

On-chain price verification using Chainlink Data Streams v10.
Verifies signed price reports and caches latest prices per feed.


## State Variables
### verifierProxy

```solidity
IVerifierProxy public immutable verifierProxy;
```


### latestPrices

```solidity
mapping(bytes32 => PriceData) public latestPrices;
```


### allowedFeeds

```solidity
mapping(bytes32 => bool) public allowedFeeds;
```


### MAX_STALENESS

```solidity
uint32 public constant MAX_STALENESS = 3600;
```


## Functions
### constructor


```solidity
constructor(address _verifierProxy, address _owner) Ownable(_owner);
```

### verifyAndCachePrice

Verify a signed Chainlink Data Streams report and cache the price.


```solidity
function verifyAndCachePrice(bytes calldata signedReport)
    external
    returns (bytes32 feedId, int192 price, uint32 timestamp);
```

### getLatestPrice

Get the latest verified price for a feed.


```solidity
function getLatestPrice(bytes32 feedId) external view returns (int192 price, uint32 timestamp);
```

### setFeedAllowed

Allow or disallow a feed ID.


```solidity
function setFeedAllowed(bytes32 feedId, bool allowed) external onlyOwner;
```

### setFeedsAllowed

Batch-allow multiple feed IDs.


```solidity
function setFeedsAllowed(bytes32[] calldata feedIds, bool allowed) external onlyOwner;
```

## Events
### PriceVerified

```solidity
event PriceVerified(bytes32 indexed feedId, int192 price, uint32 timestamp);
```

### FeedAllowed

```solidity
event FeedAllowed(bytes32 indexed feedId, bool allowed);
```

## Errors
### FeedNotAllowed

```solidity
error FeedNotAllowed(bytes32 feedId);
```

### StalePrice

```solidity
error StalePrice(bytes32 feedId, uint32 reportTimestamp, uint32 currentTimestamp);
```

### InvalidPrice

```solidity
error InvalidPrice(bytes32 feedId, int192 price);
```

## Structs
### PriceData

```solidity
struct PriceData {
    int192 price;
    uint32 timestamp;
}
```

