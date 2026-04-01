# IPyth
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/PythAdapter.sol)

Minimal Pyth interface (pull-based oracle)


## Functions
### getPriceNoOlderThan


```solidity
function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory price);
```

### getPriceUnsafe


```solidity
function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
```

### updatePriceFeeds


```solidity
function updatePriceFeeds(bytes[] calldata priceUpdateData) external payable;
```

### getUpdateFee


```solidity
function getUpdateFee(bytes[] calldata priceUpdateData) external view returns (uint256 feeAmount);
```

## Structs
### Price

```solidity
struct Price {
    int64 price;
    uint64 conf;
    int32 expo;
    uint256 publishTime;
}
```

