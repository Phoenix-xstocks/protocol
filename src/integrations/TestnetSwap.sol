// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOneInchSwapper } from "../interfaces/IOneInchSwapper.sol";

/// @title TestnetSwap
/// @notice Simple fixed-price swap for Ink Sepolia testnet.
///         Implements IOneInchSwapper so it can plug into HedgeManager directly.
///         Since no DEX exists on Ink Sepolia, this provides
///         USDC <-> xStock swaps at configurable oracle prices.
///         TESTNET ONLY — not for production use.
contract TestnetSwap is IOneInchSwapper, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable USDC;

    /// @notice Price of each xStock in USDC (6 decimals).
    ///         e.g., NVDAx at $130 → prices[NVDAx] = 130e6
    mapping(address => uint256) public prices;

    event PriceSet(address indexed token, uint256 priceUsdc);
    event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(address _usdc, address _owner) Ownable(_owner) {
        require(_usdc != address(0), "zero usdc");
        USDC = IERC20(_usdc);
    }

    /// @notice Set the USDC price for an xStock token
    function setPrice(address token, uint256 priceUsdc) external onlyOwner {
        prices[token] = priceUsdc;
        emit PriceSet(token, priceUsdc);
    }

    /// @notice Swap tokenIn for tokenOut.
    ///         Supports: USDC → xStock and xStock → USDC
    function swap(address tokenIn, address tokenOut, uint256 amountIn)
        external
        override
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "zero amount");
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        if (tokenIn == address(USDC)) {
            // USDC → xStock: amountOut = amountIn * 1e18 / priceUsdc
            uint256 price = prices[tokenOut];
            require(price > 0, "price not set");
            amountOut = (amountIn * 1e18) / price;
        } else if (tokenOut == address(USDC)) {
            // xStock → USDC: amountOut = amountIn * priceUsdc / 1e18
            uint256 price = prices[tokenIn];
            require(price > 0, "price not set");
            amountOut = (amountIn * price) / 1e18;
        } else {
            revert("unsupported pair");
        }

        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Same as swap but with minAmountOut parameter (for OneInchSwapper compatibility)
    function swapWithSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external override returns (uint256 amountOut) {
        require(amountIn > 0, "zero amount");
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        if (tokenIn == address(USDC)) {
            uint256 price = prices[tokenOut];
            require(price > 0, "price not set");
            amountOut = (amountIn * 1e18) / price;
        } else if (tokenOut == address(USDC)) {
            uint256 price = prices[tokenIn];
            require(price > 0, "price not set");
            amountOut = (amountIn * price) / 1e18;
        } else {
            revert("unsupported pair");
        }

        require(amountOut >= minAmountOut, "insufficient output");
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Deposit liquidity (owner adds USDC + xStocks for swaps)
    function addLiquidity(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraw liquidity
    function removeLiquidity(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
