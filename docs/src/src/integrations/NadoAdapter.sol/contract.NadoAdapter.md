# NadoAdapter
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/NadoAdapter.sol)

**Inherits:**
[INadoAdapter](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/INadoAdapter.sol/interface.INadoAdapter.md), Ownable, ReentrancyGuard

Adapter for Nado stock perps on Ink. Opens/closes shorts and claims funding.


## State Variables
### nadoPerp

```solidity
INadoPerp public immutable nadoPerp;
```


### marginToken

```solidity
IERC20 public immutable marginToken;
```


### positions

```solidity
mapping(bytes32 => Position) public positions;
```


## Functions
### constructor


```solidity
constructor(address _nadoPerp, address _marginToken, address _owner) Ownable(_owner);
```

### openShort


```solidity
function openShort(uint256 pairIndex, uint256 notional, uint256 leverage)
    external
    onlyOwner
    nonReentrant
    returns (bytes32 positionId);
```

### closeShort


```solidity
function closeShort(bytes32 positionId) external onlyOwner nonReentrant returns (uint256 pnl);
```

### claimFunding


```solidity
function claimFunding(bytes32 positionId) external onlyOwner nonReentrant returns (uint256 fundingAmount);
```

### getPosition


```solidity
function getPosition(bytes32 positionId)
    external
    view
    returns (int256 unrealizedPnl, uint256 margin, uint256 size, uint256 accumulatedFunding);
```

### recoverToken

Recover tokens sent to this contract by mistake.


```solidity
function recoverToken(address token, uint256 amount) external onlyOwner;
```

## Events
### ShortOpened

```solidity
event ShortOpened(bytes32 indexed positionId, uint256 pairIndex, uint256 notional, uint256 leverage);
```

### ShortClosed

```solidity
event ShortClosed(bytes32 indexed positionId, uint256 pnl);
```

### FundingClaimed

```solidity
event FundingClaimed(bytes32 indexed positionId, uint256 fundingAmount);
```

## Errors
### PositionNotOpen

```solidity
error PositionNotOpen(bytes32 positionId);
```

### PositionAlreadyExists

```solidity
error PositionAlreadyExists(bytes32 positionId);
```

## Structs
### Position

```solidity
struct Position {
    uint256 pairIndex;
    uint256 notional;
    uint256 leverage;
    bool open;
}
```

