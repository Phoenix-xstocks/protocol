# ReserveFund
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/periphery/ReserveFund.sol)

**Inherits:**
[IReserveFund](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IReserveFund.sol/interface.IReserveFund.md), Ownable, ReentrancyGuard

Buffer for coupon smoothing (Ethena model) with Euler V2 yield.
Idle USDC reserves are deposited into Euler V2 vault to earn lending yield.
On deficit, withdraws from Euler to cover coupon shortfalls.
Levels: TARGET=10%, MINIMUM=3%, CRITICAL=1% of notional outstanding.


## State Variables
### BPS

```solidity
uint256 public constant BPS = 10000;
```


### TARGET_BPS

```solidity
uint256 public constant TARGET_BPS = 1000;
```


### MINIMUM_BPS

```solidity
uint256 public constant MINIMUM_BPS = 300;
```


### CRITICAL_BPS

```solidity
uint256 public constant CRITICAL_BPS = 100;
```


### usdc

```solidity
IERC20 public usdc;
```


### balance

```solidity
uint256 public balance;
```


### eulerVault
Euler V2 vault for yield on idle reserves (optional)


```solidity
IEulerVault public eulerVault;
```


### eulerPrincipal

```solidity
uint256 public eulerPrincipal;
```


## Functions
### constructor


```solidity
constructor(address _usdc, address _owner) Ownable(_owner);
```

### setEulerVault

Set the Euler V2 vault for yield generation. Admin only.


```solidity
function setEulerVault(address _eulerVault) external onlyOwner;
```

### depositToEuler

Deposit idle USDC into Euler vault for yield


```solidity
function depositToEuler(uint256 amount) external onlyOwner nonReentrant;
```

### withdrawFromEuler

Withdraw USDC from Euler vault back to reserve


```solidity
function withdrawFromEuler(uint256 amount) external onlyOwner nonReentrant;
```

### getTotalValue

Get total reserve value including Euler yield


```solidity
function getTotalValue() public view returns (uint256);
```

### deposit


```solidity
function deposit(uint256 amount) external onlyOwner nonReentrant;
```

### coverDeficit

Covers deficit by first using local USDC, then withdrawing from Euler if needed.


```solidity
function coverDeficit(uint256 amount) external onlyOwner nonReentrant returns (uint256 covered);
```

### getBalance

Returns total value (local USDC + Euler deposits including yield)


```solidity
function getBalance() external view returns (uint256);
```

### getLevel


```solidity
function getLevel(uint256 totalNotional) external view returns (uint256 levelBps);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`levelBps`|`uint256`|Reserve level as bps of totalNotional (includes Euler yield)|


### getHaircutRatio

Returns haircut ratio in BPS (10000 = no haircut, 5000 = 50% haircut)


```solidity
function getHaircutRatio(uint256 totalNotional) external view returns (uint256 ratioBps);
```

### isBelowMinimum

Check if reserve is below minimum (includes Euler value)


```solidity
function isBelowMinimum(uint256 totalNotional) external view returns (bool);
```

### isCritical

Check if reserve is below critical (includes Euler value)


```solidity
function isCritical(uint256 totalNotional) external view returns (bool);
```

### getEulerYield

Get yield earned from Euler (value above principal)


```solidity
function getEulerYield() external view returns (uint256);
```

## Events
### Deposited

```solidity
event Deposited(uint256 amount, uint256 newBalance);
```

### DeficitCovered

```solidity
event DeficitCovered(uint256 requested, uint256 covered, uint256 newBalance);
```

### EulerVaultSet

```solidity
event EulerVaultSet(address vault);
```

### DepositedToEuler

```solidity
event DepositedToEuler(uint256 amount, uint256 shares);
```

### WithdrawnFromEuler

```solidity
event WithdrawnFromEuler(uint256 amount);
```

