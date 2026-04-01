# IAggregationRouter
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/OneInchSwapper.sol)

Minimal interface for the 1inch AggregationRouter.


## Functions
### swap


```solidity
function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
    external
    returns (uint256 amountOut);
```

