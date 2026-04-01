# FeeCollector
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/periphery/FeeCollector.sol)

**Inherits:**
[IFeeCollector](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IFeeCollector.sol/interface.IFeeCollector.md), Ownable, ReentrancyGuard

Fee collection and distribution for xYield Protocol.
Embedded: 0.5% at deposit
Origination: 0.1% at deposit
Management: 0.25% ann, pro-rata each epoch (48h)
Performance: 10% of carry net, each epoch


## State Variables
### BPS

```solidity
uint256 public constant BPS = 10000;
```


### EMBEDDED_FEE_BPS

```solidity
uint256 public constant EMBEDDED_FEE_BPS = 50;
```


### ORIGINATION_FEE_BPS

```solidity
uint256 public constant ORIGINATION_FEE_BPS = 10;
```


### MANAGEMENT_FEE_BPS

```solidity
uint256 public constant MANAGEMENT_FEE_BPS = 25;
```


### PERFORMANCE_FEE_BPS

```solidity
uint256 public constant PERFORMANCE_FEE_BPS = 1000;
```


### SECONDS_PER_YEAR

```solidity
uint256 public constant SECONDS_PER_YEAR = 365 days;
```


### usdc

```solidity
IERC20 public usdc;
```


### treasury

```solidity
address public treasury;
```


### totalCollected

```solidity
uint256 public totalCollected;
```


## Functions
### constructor


```solidity
constructor(address _usdc, address _treasury, address _owner) Ownable(_owner);
```

### collectEmbeddedFee


```solidity
function collectEmbeddedFee(uint256 notional) external onlyOwner nonReentrant returns (uint256 fee);
```

### collectOriginationFee


```solidity
function collectOriginationFee(uint256 notional) external onlyOwner nonReentrant returns (uint256 fee);
```

### collectManagementFee


```solidity
function collectManagementFee(uint256 notional, uint256 elapsed)
    external
    onlyOwner
    nonReentrant
    returns (uint256 fee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`notional`|`uint256`|Total notional outstanding|
|`elapsed`|`uint256`|Seconds since last collection|


### collectPerformanceFee


```solidity
function collectPerformanceFee(uint256 carryNet) external onlyOwner nonReentrant returns (uint256 fee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`carryNet`|`uint256`|Net carry amount for the epoch|


### getTotalCollected


```solidity
function getTotalCollected() external view returns (uint256);
```

### setTreasury

Update treasury address


```solidity
function setTreasury(address _treasury) external onlyOwner;
```

## Events
### EmbeddedFeeCollected

```solidity
event EmbeddedFeeCollected(uint256 notional, uint256 fee);
```

### OriginationFeeCollected

```solidity
event OriginationFeeCollected(uint256 notional, uint256 fee);
```

### ManagementFeeCollected

```solidity
event ManagementFeeCollected(uint256 notional, uint256 elapsed, uint256 fee);
```

### PerformanceFeeCollected

```solidity
event PerformanceFeeCollected(uint256 carryNet, uint256 fee);
```

### TreasuryUpdated

```solidity
event TreasuryUpdated(address newTreasury);
```

