# PythAdapter
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/PythAdapter.sol)

**Inherits:**
Ownable

Price feed adapter using Pyth Network on Ink.
Pull-based: caller must update prices before reading them.
Supports equity price feeds (NVDA, TSLA, META, SPY, QQQ, etc.)
Pyth on Ink Sepolia: 0x2880aB155794e7179c9eE2e38200202908C17B43


## State Variables
### pyth

```solidity
IPyth public immutable pyth;
```


### feedIds
Maps xStock address -> Pyth price feed ID


```solidity
mapping(address => bytes32) public feedIds;
```


### maxPriceAge
Max price age for reads (seconds)


```solidity
uint256 public maxPriceAge = 24 hours;
```


## Functions
### constructor


```solidity
constructor(address _pyth, address _owner) Ownable(_owner);
```

### setFeedId

Set Pyth feed ID for an xStock token


```solidity
function setFeedId(address asset, bytes32 feedId) external onlyOwner;
```

### setFeedIds

Batch set feed IDs


```solidity
function setFeedIds(address[] calldata assets, bytes32[] calldata _feedIds) external onlyOwner;
```

### updatePrices

Update price feeds (must be called before getLatestPrice).
Caller sends VAA data from Pyth Hermes API.
Requires msg.value to cover the update fee.


```solidity
function updatePrices(bytes[] calldata priceUpdateData) external payable;
```

### getLatestPrice

Get latest price for an xStock. Compatible with IPriceFeed interface.


```solidity
function getLatestPrice(bytes32 feedId) external view returns (int192 price, uint32 timestamp);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`price`|`int192`|Price in 8-decimal format (same as Chainlink)|
|`timestamp`|`uint32`|Publication timestamp|


### getPriceByAsset

Get price for an xStock by its token address


```solidity
function getPriceByAsset(address asset) external view returns (int192 price, uint32 timestamp);
```

### setMaxPriceAge


```solidity
function setMaxPriceAge(uint256 newAge) external onlyOwner;
```

### recoverETH

Recover ETH sent to this contract


```solidity
function recoverETH() external onlyOwner;
```

### receive


```solidity
receive() external payable;
```

## Events
### FeedIdSet

```solidity
event FeedIdSet(address indexed asset, bytes32 feedId);
```

### PricesUpdated

```solidity
event PricesUpdated(uint256 count, uint256 fee);
```

### MaxPriceAgeUpdated

```solidity
event MaxPriceAgeUpdated(uint256 newAge);
```

## Errors
### StalePrice

```solidity
error StalePrice(address asset, uint256 publishTime);
```

### FeedNotConfigured

```solidity
error FeedNotConfigured(address asset);
```

### InvalidPrice

```solidity
error InvalidPrice(address asset, int64 price);
```

