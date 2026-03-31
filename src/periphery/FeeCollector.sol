// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IFeeCollector } from "../interfaces/IFeeCollector.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FeeCollector
/// @notice Fee collection and distribution for xYield Protocol.
///         Embedded: 0.5% at deposit
///         Origination: 0.1% at deposit
///         Management: 0.25% ann, pro-rata each epoch (48h)
///         Performance: 10% of carry net, each epoch
contract FeeCollector is IFeeCollector, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10000;
    uint256 public constant EMBEDDED_FEE_BPS = 50; // 0.5%
    uint256 public constant ORIGINATION_FEE_BPS = 10; // 0.1%
    uint256 public constant MANAGEMENT_FEE_BPS = 25; // 0.25% annualized
    uint256 public constant PERFORMANCE_FEE_BPS = 1000; // 10% of carry
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    IERC20 public usdc;
    address public treasury;
    uint256 public totalCollected;

    event EmbeddedFeeCollected(uint256 notional, uint256 fee);
    event OriginationFeeCollected(uint256 notional, uint256 fee);
    event ManagementFeeCollected(uint256 notional, uint256 elapsed, uint256 fee);
    event PerformanceFeeCollected(uint256 carryNet, uint256 fee);
    event TreasuryUpdated(address newTreasury);

    constructor(address _usdc, address _treasury, address _owner) Ownable(_owner) {
        require(_usdc != address(0), "zero usdc");
        require(_treasury != address(0), "zero treasury");
        usdc = IERC20(_usdc);
        treasury = _treasury;
    }

    /// @inheritdoc IFeeCollector
    function collectEmbeddedFee(uint256 notional) external onlyOwner nonReentrant returns (uint256 fee) {
        fee = (notional * EMBEDDED_FEE_BPS) / BPS;
        if (fee > 0) {
            usdc.safeTransferFrom(msg.sender, treasury, fee);
            totalCollected += fee;
        }
        emit EmbeddedFeeCollected(notional, fee);
    }

    /// @inheritdoc IFeeCollector
    function collectOriginationFee(uint256 notional) external onlyOwner nonReentrant returns (uint256 fee) {
        fee = (notional * ORIGINATION_FEE_BPS) / BPS;
        if (fee > 0) {
            usdc.safeTransferFrom(msg.sender, treasury, fee);
            totalCollected += fee;
        }
        emit OriginationFeeCollected(notional, fee);
    }

    /// @inheritdoc IFeeCollector
    /// @param notional Total notional outstanding
    /// @param elapsed Seconds since last collection
    function collectManagementFee(
        uint256 notional,
        uint256 elapsed
    ) external onlyOwner nonReentrant returns (uint256 fee) {
        // 0.25% annualized, pro-rata for elapsed time
        fee = (notional * MANAGEMENT_FEE_BPS * elapsed) / (BPS * SECONDS_PER_YEAR);
        if (fee > 0) {
            usdc.safeTransferFrom(msg.sender, treasury, fee);
            totalCollected += fee;
        }
        emit ManagementFeeCollected(notional, elapsed, fee);
    }

    /// @inheritdoc IFeeCollector
    /// @param carryNet Net carry amount for the epoch
    function collectPerformanceFee(uint256 carryNet) external onlyOwner nonReentrant returns (uint256 fee) {
        // 10% of carry net
        fee = (carryNet * PERFORMANCE_FEE_BPS) / BPS;
        if (fee > 0) {
            usdc.safeTransferFrom(msg.sender, treasury, fee);
            totalCollected += fee;
        }
        emit PerformanceFeeCollected(carryNet, fee);
    }

    /// @inheritdoc IFeeCollector
    function getTotalCollected() external view returns (uint256) {
        return totalCollected;
    }

    /// @notice Update treasury address
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "zero treasury");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }
}
