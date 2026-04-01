# ProtocolStats
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/periphery/ProtocolStats.sol)

Read-only aggregator for protocol-wide dashboard metrics.
All view functions — no state changes, no gas cost.


## State Variables
### engine

```solidity
IAutocallEngine public immutable engine;
```


### vault

```solidity
IXYieldVault public immutable vault;
```


### reserveFund

```solidity
IReserveFund public immutable reserveFund;
```


### usdc

```solidity
IERC20 public immutable usdc;
```


## Functions
### constructor


```solidity
constructor(address _engine, address _vault, address _reserveFund, address _usdc);
```

### getStats

Get all protocol stats in a single call


```solidity
function getStats(uint256 totalNotional) external view returns (Stats memory stats);
```

## Structs
### Stats

```solidity
struct Stats {
    uint256 totalNotesCreated;
    uint256 tvl;
    uint256 maxDeposit;
    uint256 reserveBalance;
    uint256 engineUsdcBalance;
    uint256 vaultUsdcBalance;
    uint256 reserveLevel;
}
```

