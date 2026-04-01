# HedgeManager
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/hedge/HedgeManager.sol)

**Inherits:**
[IHedgeManager](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IHedgeManager.sol/interface.IHedgeManager.md), Ownable, ReentrancyGuard

Orchestrates spot + perps + collateral for delta-neutral hedge.
Open/close/rebalance with delta drift monitoring and circuit breaker.


## State Variables
### BPS

```solidity
uint256 public constant BPS = 10000;
```


### DELTA_THRESHOLD_BPS

```solidity
uint256 public constant DELTA_THRESHOLD_BPS = 500;
```


### DELTA_CRITICAL_BPS

```solidity
uint256 public constant DELTA_CRITICAL_BPS = 1500;
```


### MAX_REBALANCE_COST

```solidity
uint256 public constant MAX_REBALANCE_COST = 50;
```


### DEFAULT_LEVERAGE

```solidity
uint256 public constant DEFAULT_LEVERAGE = 1;
```


### nado

```solidity
INadoAdapter public nado;
```


### tydro

```solidity
ITydroAdapter public tydro;
```


### swapper

```solidity
IOneInchSwapper public swapper;
```


### usdc

```solidity
IERC20 public usdc;
```


### authorized
Authorized callers (AutocallEngine, EpochManager, etc.)


```solidity
mapping(address => bool) public authorized;
```


### testnetMode
Testnet mode: skip Nado perp operations only (no perp DEX on Ink testnet).
Tydro collateral operations always run (xStocks are live on Tydro).


```solidity
bool public testnetMode;
```


### positions

```solidity
mapping(bytes32 => HedgePosition) internal positions;
```


### pairIndexes

```solidity
mapping(address => uint256) public pairIndexes;
```


### notePaused
Per-note circuit breaker pausing


```solidity
mapping(bytes32 => bool) public notePaused;
```


## Functions
### onlyAuthorized


```solidity
modifier onlyAuthorized();
```

### setAuthorized


```solidity
function setAuthorized(address account, bool status) external onlyOwner;
```

### setTestnetMode


```solidity
function setTestnetMode(bool _testnet) external onlyOwner;
```

### constructor


```solidity
constructor(address _nado, address _tydro, address _swapper, address _usdc, address _owner) Ownable(_owner);
```

### setPairIndex

Set pair index for a given xStock asset


```solidity
function setPairIndex(address asset, uint256 pairIndex) external onlyOwner;
```

### openHedge


```solidity
function openHedge(bytes32 noteId, address[] calldata basket, uint256 notional) external onlyAuthorized nonReentrant;
```

### closeHedge


```solidity
function closeHedge(bytes32 noteId) external onlyAuthorized nonReentrant returns (uint256 recovered);
```

### rebalance


```solidity
function rebalance(bytes32 noteId) external nonReentrant;
```

### getDeltaDrift


```solidity
function getDeltaDrift(bytes32 noteId) external view returns (int256 driftBps);
```

### getPosition

Get position details


```solidity
function getPosition(bytes32 noteId)
    external
    view
    returns (uint256 notional, uint256 spotNotional, uint256 borrowed, bool active);
```

### unpauseNote

Unpause a specific note after emergency (owner only, e.g. multisig)


```solidity
function unpauseNote(bytes32 noteId) external onlyOwner;
```

### _calculateDeltaDrift


```solidity
function _calculateDeltaDrift(bytes32 noteId) internal view returns (int256);
```

### _adjustPerps

Adjust perp positions to match current spot values.
Only adjusts positions where drift exceeds per-stock threshold.


```solidity
function _adjustPerps(bytes32 noteId, int256) internal;
```

### _abs


```solidity
function _abs(int256 x) internal pure returns (uint256);
```

## Events
### HedgeOpened

```solidity
event HedgeOpened(bytes32 indexed noteId, uint256 notional, uint256 spotNotional, uint256 borrowed);
```

### HedgeClosed

```solidity
event HedgeClosed(bytes32 indexed noteId, uint256 recovered, int256 pnl);
```

### HedgeRebalanced

```solidity
event HedgeRebalanced(bytes32 indexed noteId, int256 deltaDrift);
```

### EmergencyPaused

```solidity
event EmergencyPaused(bytes32 indexed noteId, string reason);
```

### PairIndexSet

```solidity
event PairIndexSet(address indexed asset, uint256 pairIndex);
```

## Structs
### StockHedge

```solidity
struct StockHedge {
    address asset;
    uint256 spotAmount;
    uint256 perpNotional;
    bytes32 positionId;
    uint256 pairIndex;
}
```

### HedgePosition

```solidity
struct HedgePosition {
    address[] basket;
    uint256 notional;
    uint256 spotNotional;
    uint256 tydroBorrowed;
    uint256 openTimestamp;
    bool active;
    mapping(uint256 => StockHedge) stocks;
    uint256 stockCount;
}
```

