// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Minimal Pyth interface (pull-based oracle)
interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint publishTime;
    }

    function getPriceNoOlderThan(bytes32 id, uint age) external view returns (Price memory price);
    function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
    function updatePriceFeeds(bytes[] calldata priceUpdateData) external payable;
    function getUpdateFee(bytes[] calldata priceUpdateData) external view returns (uint feeAmount);
}

/// @title PythAdapter
/// @notice Price feed adapter using Pyth Network on Ink.
///         Pull-based: caller must update prices before reading them.
///         Supports equity price feeds (NVDA, TSLA, META, SPY, QQQ, etc.)
///
///         Pyth on Ink Sepolia: 0x2880aB155794e7179c9eE2e38200202908C17B43
contract PythAdapter is Ownable {
    IPyth public immutable pyth;

    /// @notice Maps xStock address -> Pyth price feed ID
    mapping(address => bytes32) public feedIds;

    /// @notice Max price age for reads (seconds)
    uint256 public maxPriceAge = 24 hours;

    event FeedIdSet(address indexed asset, bytes32 feedId);
    event PricesUpdated(uint256 count, uint256 fee);
    event MaxPriceAgeUpdated(uint256 newAge);

    error StalePrice(address asset, uint256 publishTime);
    error FeedNotConfigured(address asset);
    error InvalidPrice(address asset, int64 price);

    constructor(address _pyth, address _owner) Ownable(_owner) {
        require(_pyth != address(0), "zero pyth");
        pyth = IPyth(_pyth);
    }

    /// @notice Set Pyth feed ID for an xStock token
    function setFeedId(address asset, bytes32 feedId) external onlyOwner {
        feedIds[asset] = feedId;
        emit FeedIdSet(asset, feedId);
    }

    /// @notice Batch set feed IDs
    function setFeedIds(address[] calldata assets, bytes32[] calldata _feedIds) external onlyOwner {
        require(assets.length == _feedIds.length, "length mismatch");
        for (uint256 i = 0; i < assets.length; i++) {
            feedIds[assets[i]] = _feedIds[i];
            emit FeedIdSet(assets[i], _feedIds[i]);
        }
    }

    /// @notice Update price feeds (must be called before getLatestPrice).
    ///         Caller sends VAA data from Pyth Hermes API.
    ///         Requires msg.value to cover the update fee.
    function updatePrices(bytes[] calldata priceUpdateData) external payable {
        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        pyth.updatePriceFeeds{ value: fee }(priceUpdateData);
        emit PricesUpdated(priceUpdateData.length, fee);

        // Refund excess ETH
        if (msg.value > fee) {
            (bool ok, ) = msg.sender.call{ value: msg.value - fee }("");
            require(ok, "refund failed");
        }
    }

    /// @notice Get latest price for an xStock. Compatible with IPriceFeed interface.
    /// @return price Price in 8-decimal format (same as Chainlink)
    /// @return timestamp Publication timestamp
    function getLatestPrice(bytes32 feedId) external view returns (int192 price, uint32 timestamp) {
        IPyth.Price memory p = pyth.getPriceNoOlderThan(feedId, maxPriceAge);
        require(p.price > 0, "invalid price");

        // Normalize to 8 decimals (Pyth uses variable expo, typically -8)
        int256 normalized;
        // Normalize to 8 decimals. Pyth expo is typically negative (e.g., -8).
        int32 targetExpo = -8;
        if (p.expo == targetExpo) {
            normalized = int256(p.price);
        } else if (p.expo > targetExpo) {
            // expo=-5, target=-8 → need MORE decimals → multiply by 10^(expo - target) = 10^3
            uint256 diff = uint256(int256(p.expo - targetExpo));
            normalized = int256(p.price) * int256(10 ** diff);
        } else {
            // expo=-10, target=-8 → need FEWER decimals → divide by 10^(target - expo) = 10^2
            uint256 diff = uint256(int256(targetExpo - p.expo));
            normalized = int256(p.price) / int256(10 ** diff);
        }

        price = int192(normalized);
        timestamp = uint32(p.publishTime);
    }

    /// @notice Get price for an xStock by its token address
    function getPriceByAsset(address asset) external view returns (int192 price, uint32 timestamp) {
        bytes32 feedId = feedIds[asset];
        if (feedId == bytes32(0)) revert FeedNotConfigured(asset);

        IPyth.Price memory p = pyth.getPriceNoOlderThan(feedId, maxPriceAge);
        if (p.price <= 0) revert InvalidPrice(asset, p.price);

        // Normalize to 8 decimals
        int256 normalized;
        int32 targetExpo = -8;
        if (p.expo == targetExpo) {
            normalized = int256(p.price);
        } else if (p.expo > targetExpo) {
            uint256 diff = uint256(int256(p.expo - targetExpo));
            normalized = int256(p.price) * int256(10 ** diff);
        } else {
            uint256 diff = uint256(int256(targetExpo - p.expo));
            normalized = int256(p.price) / int256(10 ** diff);
        }

        price = int192(normalized);
        timestamp = uint32(p.publishTime);
    }

    function setMaxPriceAge(uint256 newAge) external onlyOwner {
        maxPriceAge = newAge;
        emit MaxPriceAgeUpdated(newAge);
    }

    /// @notice Recover ETH sent to this contract
    function recoverETH() external onlyOwner {
        (bool ok, ) = msg.sender.call{ value: address(this).balance }("");
        require(ok, "transfer failed");
    }

    receive() external payable {}
}
