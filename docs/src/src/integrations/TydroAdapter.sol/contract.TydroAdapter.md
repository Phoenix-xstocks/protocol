# TydroAdapter
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/TydroAdapter.sol)

**Inherits:**
[ITydroAdapter](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/ITydroAdapter.sol/interface.ITydroAdapter.md), Ownable, ReentrancyGuard

Adapter for Tydro (Aave v3 fork on Ink). Manages collateral, borrowing, and lending.


## State Variables
### tydroPool

```solidity
ITydroPool public immutable tydroPool;
```


### usdc

```solidity
IERC20 public immutable usdc;
```


### VARIABLE_RATE_MODE

```solidity
uint256 private constant VARIABLE_RATE_MODE = 2;
```


### SECONDS_PER_YEAR

```solidity
uint256 private constant SECONDS_PER_YEAR = 365 days;
```


### RAY

```solidity
uint256 private constant RAY = 1e27;
```


## Functions
### constructor


```solidity
constructor(address _tydroPool, address _usdc, address _owner) Ownable(_owner);
```

### depositCollateral


```solidity
function depositCollateral(address asset, uint256 amount) external onlyOwner nonReentrant;
```

### withdrawCollateral


```solidity
function withdrawCollateral(address asset) external onlyOwner nonReentrant returns (uint256 amount);
```

### borrowUSDC


```solidity
function borrowUSDC(uint256 amount) external onlyOwner nonReentrant returns (uint256 borrowed);
```

### repayUSDC


```solidity
function repayUSDC(uint256 amount) external onlyOwner nonReentrant;
```

### getCollateralValue

Returns per-asset collateral value using the aToken balance


```solidity
function getCollateralValue(address asset) external view returns (uint256);
```

### getLendingRate

Aave returns liquidity rate as a ray (1e27). Convert to wad (1e18) per-second.


```solidity
function getLendingRate() external view returns (uint256 ratePerSecond);
```

### depositUSDC


```solidity
function depositUSDC(uint256 amount) external onlyOwner nonReentrant;
```

### withdrawUSDC


```solidity
function withdrawUSDC(uint256 amount) external onlyOwner nonReentrant returns (uint256 withdrawn);
```

### recoverToken

Recover tokens sent to this contract by mistake.


```solidity
function recoverToken(address token, uint256 amount) external onlyOwner;
```

## Events
### CollateralDeposited

```solidity
event CollateralDeposited(address indexed asset, uint256 amount);
```

### CollateralWithdrawn

```solidity
event CollateralWithdrawn(address indexed asset, uint256 amount);
```

### USDCBorrowed

```solidity
event USDCBorrowed(uint256 amount);
```

### USDCRepaid

```solidity
event USDCRepaid(uint256 amount);
```

### USDCDeposited

```solidity
event USDCDeposited(uint256 amount);
```

### USDCWithdrawn

```solidity
event USDCWithdrawn(uint256 amount);
```

