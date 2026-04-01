# IssuanceGate
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/pricing/IssuanceGate.sol)

**Inherits:**
[IIssuanceGate](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IIssuanceGate.sol/interface.IIssuanceGate.md), Ownable

4 pre-checks before note emission:
1. Pricing accepted by CREConsumer
2. HedgeManager reports capacity
3. ReserveFund above minimum (3%)
4. Active notes < MAX_ACTIVE_NOTES, notional within limits


## State Variables
### BPS

```solidity
uint256 public constant BPS = 10000;
```


### MAX_ACTIVE_NOTES

```solidity
uint256 public constant MAX_ACTIVE_NOTES = 500;
```


### MIN_NOTE_SIZE

```solidity
uint256 public constant MIN_NOTE_SIZE = 100e6;
```


### MAX_NOTE_SIZE

```solidity
uint256 public constant MAX_NOTE_SIZE = 100_000e6;
```


### RESERVE_MINIMUM_BPS

```solidity
uint256 public constant RESERVE_MINIMUM_BPS = 300;
```


### MAX_TVL

```solidity
uint256 public constant MAX_TVL = 5_000_000e6;
```


### creConsumer

```solidity
ICREConsumer public creConsumer;
```


### hedgeManager

```solidity
IHedgeManager public hedgeManager;
```


### reserveFund

```solidity
IReserveFund public reserveFund;
```


### activeNoteCount

```solidity
uint256 public activeNoteCount;
```


### totalNotionalOutstanding

```solidity
uint256 public totalNotionalOutstanding;
```


### authorized
Authorized callers (AutocallEngine)


```solidity
mapping(address => bool) public authorized;
```


## Functions
### constructor


```solidity
constructor(address _creConsumer, address _hedgeManager, address _reserveFund, address _owner) Ownable(_owner);
```

### checkIssuance


```solidity
function checkIssuance(bytes32 noteId, uint256 notional, address[] calldata)
    external
    view
    returns (bool approved, string memory reason);
```

### setAuthorized


```solidity
function setAuthorized(address account, bool status) external onlyOwner;
```

### onlyAuthorizedOrOwner


```solidity
modifier onlyAuthorizedOrOwner();
```

### noteActivated


```solidity
function noteActivated(uint256 notional) external onlyAuthorizedOrOwner;
```

### noteSettled


```solidity
function noteSettled(uint256 notional) external onlyAuthorizedOrOwner;
```

### setDependencies


```solidity
function setDependencies(address _creConsumer, address _hedgeManager, address _reserveFund) external onlyOwner;
```

## Events
### DependenciesUpdated

```solidity
event DependenciesUpdated(address creConsumer, address hedgeManager, address reserveFund);
```

