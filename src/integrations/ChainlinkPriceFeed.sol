// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Minimal interface for Chainlink Data Streams verifier on Ink.
interface IVerifierProxy {
    function verify(bytes calldata signedReport) external payable returns (bytes memory verifiedReportData);
}

/// @title ChainlinkPriceFeed
/// @notice On-chain price verification using Chainlink Data Streams v10.
///         Verifies signed price reports and caches latest prices per feed.
contract ChainlinkPriceFeed is Ownable {
    IVerifierProxy public immutable VERIFIER_PROXY;

    struct PriceData {
        int192 price;
        uint32 timestamp;
    }

    mapping(bytes32 => PriceData) public latestPrices;
    mapping(bytes32 => bool) public allowedFeeds;

    event PriceVerified(bytes32 indexed feedId, int192 price, uint32 timestamp);
    event FeedAllowed(bytes32 indexed feedId, bool allowed);

    error FeedNotAllowed(bytes32 feedId);
    error StalePrice(bytes32 feedId, uint32 reportTimestamp, uint32 currentTimestamp);
    error InvalidPrice(bytes32 feedId, int192 price);

    uint32 public constant MAX_STALENESS = 3600;

    constructor(address _verifierProxy, address _owner) Ownable(_owner) {
        VERIFIER_PROXY = IVerifierProxy(_verifierProxy);
    }

    /// @notice Verify a signed Chainlink Data Streams report and cache the price.
    function verifyAndCachePrice(bytes calldata signedReport)
        external
        returns (bytes32 feedId, int192 price, uint32 timestamp)
    {
        bytes memory verifiedData = VERIFIER_PROXY.verify(signedReport);

        // Data Streams v10 report: feedId, validFromTimestamp, observationsTimestamp,
        // nativeFee, linkFee, expiresAt, price, bid, ask
        (feedId,, timestamp,,,,price,,) = abi.decode(
            verifiedData,
            (bytes32, uint32, uint32, uint192, uint192, uint32, int192, int192, int192)
        );

        if (!allowedFeeds[feedId]) revert FeedNotAllowed(feedId);
        if (price <= 0) revert InvalidPrice(feedId, price);
        if (block.timestamp - timestamp > MAX_STALENESS) {
            revert StalePrice(feedId, timestamp, uint32(block.timestamp));
        }

        latestPrices[feedId] = PriceData({ price: price, timestamp: timestamp });
        emit PriceVerified(feedId, price, timestamp);
    }

    /// @notice Get the latest verified price for a feed.
    function getLatestPrice(bytes32 feedId) external view returns (int192 price, uint32 timestamp) {
        PriceData memory data = latestPrices[feedId];
        return (data.price, data.timestamp);
    }

    /// @notice Allow or disallow a feed ID.
    function setFeedAllowed(bytes32 feedId, bool allowed) external onlyOwner {
        allowedFeeds[feedId] = allowed;
        emit FeedAllowed(feedId, allowed);
    }

    /// @notice Batch-allow multiple feed IDs.
    function setFeedsAllowed(bytes32[] calldata feedIds, bool allowed) external onlyOwner {
        for (uint256 i = 0; i < feedIds.length; i++) {
            allowedFeeds[feedIds[i]] = allowed;
            emit FeedAllowed(feedIds[i], allowed);
        }
    }
}
