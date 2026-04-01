# TestnetSwap
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/TestnetSwap.sol)

**Inherits:**
[IOneInchSwapper](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IOneInchSwapper.sol/interface.IOneInchSwapper.md), Ownable

Simple fixed-price swap for Ink Sepolia testnet.
Implements IOneInchSwapper so it can plug into HedgeManager directly.
Since no DEX exists on Ink Sepolia, this provides
USDC <-> xStock swaps at configurable oracle prices.
TESTNET ONLY — not for production use.


## State Variables
### usdc

```solidity
IERC20 public immutable usdc;
```


### prices
Price of each xStock in USDC (6 decimals).
e.g., NVDAx at $130 → prices[NVDAx] = 130e6


```solidity
mapping(address => uint256) public prices;
```


## Functions
### constructor


```solidity
constructor(address _usdc, address _owner) Ownable(_owner);
```

### setPrice

Set the USDC price for an xStock token


```solidity
function setPrice(address token, uint256 priceUsdc) external onlyOwner;
```

### swap

Swap tokenIn for tokenOut.
Supports: USDC → xStock and xStock → USDC


```solidity
function swap(address tokenIn, address tokenOut, uint256 amountIn) external override returns (uint256 amountOut);
```

### swapWithSlippage

Same as swap but with minAmountOut parameter (for OneInchSwapper compatibility)


```solidity
function swapWithSlippage(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
    external
    override
    returns (uint256 amountOut);
```

### addLiquidity

Deposit liquidity (owner adds USDC + xStocks for swaps)


```solidity
function addLiquidity(address token, uint256 amount) external onlyOwner;
```

### removeLiquidity

Withdraw liquidity


```solidity
function removeLiquidity(address token, uint256 amount) external onlyOwner;
```

## Events
### PriceSet

```solidity
event PriceSet(address indexed token, uint256 priceUsdc);
```

### Swapped

```solidity
event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
```

