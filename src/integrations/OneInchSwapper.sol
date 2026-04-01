// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOneInchSwapper } from "../interfaces/IOneInchSwapper.sol";

/// @notice Minimal interface for the 1inch AggregationRouter.
interface IAggregationRouter {
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut);
}

/// @title OneInchSwapper
/// @notice Swap adapter with retry (3x) and slippage control via 1inch on Ink.
contract OneInchSwapper is IOneInchSwapper, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IAggregationRouter public immutable ROUTER;

    /// @dev Maximum number of retry attempts per swap.
    uint256 public constant MAX_RETRIES = 3;
    /// @dev Default slippage tolerance in basis points (50 = 0.5%).
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 50;
    /// @dev Slippage increment per retry in basis points (50 = 0.5%).
    uint256 public constant RETRY_SLIPPAGE_INCREMENT_BPS = 50;
    uint256 private constant BPS = 10_000;

    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event SwapRetried(uint256 attempt, uint256 slippageBps);

    error SwapFailed(uint256 attempts);
    error InsufficientOutput(uint256 amountOut, uint256 minAmountOut);

    constructor(address _router, address _owner) Ownable(_owner) {
        ROUTER = IAggregationRouter(_router);
    }

    /// @inheritdoc IOneInchSwapper
    function swap(address tokenIn, address tokenOut, uint256 amountIn)
        external
        onlyOwner
        nonReentrant
        returns (uint256 amountOut)
    {
        amountOut = _swapWithRetry(tokenIn, tokenOut, amountIn, 0);
    }

    /// @inheritdoc IOneInchSwapper
    function swapWithSlippage(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        external
        onlyOwner
        nonReentrant
        returns (uint256 amountOut)
    {
        amountOut = _swapWithRetry(tokenIn, tokenOut, amountIn, minAmountOut);
    }

    /// @dev Internal swap logic with up to MAX_RETRIES attempts.
    ///      Each retry increases slippage tolerance by RETRY_SLIPPAGE_INCREMENT_BPS.
    function _swapWithRetry(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        internal
        returns (uint256 amountOut)
    {
        IERC20(tokenIn).forceApprove(address(ROUTER), amountIn);

        for (uint256 i = 0; i < MAX_RETRIES; i++) {
            uint256 currentSlippageBps = DEFAULT_SLIPPAGE_BPS + (i * RETRY_SLIPPAGE_INCREMENT_BPS);
            uint256 effectiveMin = minAmountOut > 0
                ? minAmountOut * (BPS - currentSlippageBps) / BPS
                : amountIn * (BPS - currentSlippageBps) / BPS;

            if (i > 0) {
                emit SwapRetried(i + 1, currentSlippageBps);
            }

            try ROUTER.swap(tokenIn, tokenOut, amountIn, effectiveMin) returns (uint256 result) {
                if (minAmountOut > 0 && result < minAmountOut) {
                    revert InsufficientOutput(result, minAmountOut);
                }
                IERC20(tokenIn).forceApprove(address(ROUTER), 0);
                emit SwapExecuted(tokenIn, tokenOut, amountIn, result);
                return result;
            } catch {
                // Continue to next retry
            }
        }

        IERC20(tokenIn).forceApprove(address(ROUTER), 0);
        revert SwapFailed(MAX_RETRIES);
    }

    /// @notice Recover tokens sent to this contract by mistake.
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
