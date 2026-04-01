# OneInchSwapper
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/OneInchSwapper.sol)

**Inherits:**
[IOneInchSwapper](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IOneInchSwapper.sol/interface.IOneInchSwapper.md), Ownable, ReentrancyGuard

Swap adapter with retry (3x) and slippage control via 1inch on Ink.


## State Variables
### router

```solidity
IAggregationRouter public immutable router;
```


### MAX_RETRIES
*Maximum number of retry attempts per swap.*


```solidity
uint256 public constant MAX_RETRIES = 3;
```


### DEFAULT_SLIPPAGE_BPS
*Default slippage tolerance in basis points (50 = 0.5%).*


```solidity
uint256 public constant DEFAULT_SLIPPAGE_BPS = 50;
```


### RETRY_SLIPPAGE_INCREMENT_BPS
*Slippage increment per retry in basis points (50 = 0.5%).*


```solidity
uint256 public constant RETRY_SLIPPAGE_INCREMENT_BPS = 50;
```


### BPS

```solidity
uint256 private constant BPS = 10_000;
```


## Functions
### constructor


```solidity
constructor(address _router, address _owner) Ownable(_owner);
```

### swap


```solidity
function swap(address tokenIn, address tokenOut, uint256 amountIn)
    external
    onlyOwner
    nonReentrant
    returns (uint256 amountOut);
```

### swapWithSlippage


```solidity
function swapWithSlippage(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
    external
    onlyOwner
    nonReentrant
    returns (uint256 amountOut);
```

### _swapWithRetry

*Internal swap logic with up to MAX_RETRIES attempts.
Each retry increases slippage tolerance by RETRY_SLIPPAGE_INCREMENT_BPS.*


```solidity
function _swapWithRetry(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
    internal
    returns (uint256 amountOut);
```

### recoverToken

Recover tokens sent to this contract by mistake.


```solidity
function recoverToken(address token, uint256 amount) external onlyOwner;
```

## Events
### SwapExecuted

```solidity
event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
```

### SwapRetried

```solidity
event SwapRetried(uint256 attempt, uint256 slippageBps);
```

## Errors
### SwapFailed

```solidity
error SwapFailed(uint256 attempts);
```

### InsufficientOutput

```solidity
error InsufficientOutput(uint256 amountOut, uint256 minAmountOut);
```

