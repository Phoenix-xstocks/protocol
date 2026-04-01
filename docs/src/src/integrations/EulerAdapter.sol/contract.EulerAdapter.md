# EulerAdapter
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/EulerAdapter.sol)

**Inherits:**
Ownable, ReentrancyGuard

Adapter for Euler V2 ERC-4626 vaults.
Used by ReserveFund to earn yield on idle USDC reserves.
Euler V2 uses the Euler Vault Kit (EVK) — permissionless vault deployment.
Integration points:
- ReserveFund deposits idle USDC → Euler USDC vault → earns lending yield
- On coverDeficit, withdraws from Euler back to cover coupon shortfalls
- Yield accrues passively via ERC-4626 share appreciation


## State Variables
### eulerVault

```solidity
IEulerVault public immutable eulerVault;
```


### usdc

```solidity
IERC20 public immutable usdc;
```


## Functions
### constructor


```solidity
constructor(address _eulerVault, address _usdc, address _owner) Ownable(_owner);
```

### deposit

Deposit USDC into Euler vault to earn yield


```solidity
function deposit(uint256 amount) external onlyOwner nonReentrant returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|USDC amount to deposit|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|Euler vault shares received|


### withdraw

Withdraw USDC from Euler vault


```solidity
function withdraw(uint256 amount) external onlyOwner nonReentrant returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|USDC amount to withdraw|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|Euler shares burned|


### withdrawAll

Withdraw all USDC from Euler vault


```solidity
function withdrawAll() external onlyOwner nonReentrant returns (uint256 assets);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|Total USDC withdrawn|


### getTotalValue

Get current USDC value of deposits in Euler (including yield)


```solidity
function getTotalValue() external view returns (uint256);
```

### getAccruedYield

Get the yield earned (value above principal)


```solidity
function getAccruedYield(uint256 principal) external view returns (uint256);
```

### getShares

Get Euler vault shares balance


```solidity
function getShares() external view returns (uint256);
```

### recoverToken

Recover tokens sent to this contract by mistake


```solidity
function recoverToken(address token, uint256 amount) external onlyOwner;
```

## Events
### Deposited

```solidity
event Deposited(uint256 assets, uint256 shares);
```

### Withdrawn

```solidity
event Withdrawn(uint256 assets, uint256 shares);
```

## Errors
### VaultAssetMismatch

```solidity
error VaultAssetMismatch();
```

### InsufficientBalance

```solidity
error InsufficientBalance();
```

