# CarryEngine
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/hedge/CarryEngine.sol)

**Inherits:**
[ICarryEngine](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/ICarryEngine.sol/interface.ICarryEngine.md), Ownable

Multi-source carry aggregator:
A: Funding rate from Nado short perps (~55% of carry)
B: USDC lending on Tydro (~35%)
C: xStocks collateral yield on Tydro (~10%)


## State Variables
### BPS

```solidity
uint256 public constant BPS = 10000;
```


### SECONDS_PER_YEAR

```solidity
uint256 public constant SECONDS_PER_YEAR = 365 days;
```


### nado

```solidity
INadoAdapter public nado;
```


### tydro

```solidity
ITydroAdapter public tydro;
```


### usdc

```solidity
IERC20 public usdc;
```


### lastFundingRateBps
Cached rates (updated each epoch)


```solidity
uint256 public lastFundingRateBps;
```


### lastLendingRateBps

```solidity
uint256 public lastLendingRateBps;
```


### lastCollateralYieldBps

```solidity
uint256 public lastCollateralYieldBps;
```


### lastUpdateTimestamp

```solidity
uint256 public lastUpdateTimestamp;
```


### totalCarryCollected
Tracks collected carry per note


```solidity
mapping(bytes32 => uint256) public totalCarryCollected;
```


### lastCollectTimestamp
Per-note last collect timestamp to avoid double-counting lending carry


```solidity
mapping(bytes32 => uint256) public lastCollectTimestamp;
```


### notePositions

```solidity
mapping(bytes32 => NotePositions) internal notePositions;
```


## Functions
### constructor


```solidity
constructor(address _nado, address _tydro, address _usdc, address _owner) Ownable(_owner);
```

### registerPositions

Register Nado positions and USDC lending for a note


```solidity
function registerPositions(bytes32 noteId, bytes32[] calldata positionIds, uint256 usdcLent) external onlyOwner;
```

### collectCarry


```solidity
function collectCarry(bytes32 noteId) external onlyOwner returns (uint256 fundingCarry, uint256 lendingCarry);
```

### getTotalCarryRate


```solidity
function getTotalCarryRate() external view returns (uint256 rateBps);
```

### getFundingRate


```solidity
function getFundingRate() external view returns (uint256 rateBps);
```

### getLendingRate


```solidity
function getLendingRate() external view returns (uint256 rateBps);
```

### updateRates

Update cached rates (called each epoch)


```solidity
function updateRates(uint256 fundingRateBps, uint256 lendingRateBps, uint256 collateralYieldBps) external onlyOwner;
```

## Events
### CarryCollected

```solidity
event CarryCollected(bytes32 indexed noteId, uint256 fundingCarry, uint256 lendingCarry, uint256 collateralYield);
```

### RatesUpdated

```solidity
event RatesUpdated(uint256 fundingRateBps, uint256 lendingRateBps, uint256 collateralYieldBps);
```

### PositionsRegistered

```solidity
event PositionsRegistered(bytes32 indexed noteId, uint256 positionCount, uint256 usdcLent);
```

## Structs
### NotePositions
Tracks Nado position IDs per note for funding collection


```solidity
struct NotePositions {
    bytes32[] positionIds;
    uint256 usdcLent;
}
```

