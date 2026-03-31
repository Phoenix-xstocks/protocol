// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ICREConsumer, PricingResult } from "../interfaces/ICREConsumer.sol";

/// @title ChainlinkCRE
/// @notice CRE workflows consumer for pricing oracle. Receives fulfillment callbacks
///         from the Chainlink CRE Router after DON consensus on Monte Carlo pricing.
contract ChainlinkCRE is ICREConsumer, Ownable {
    address public immutable creRouter;

    uint16 public constant MIN_PREMIUM = 300;
    uint16 public constant MAX_PREMIUM = 1500;
    uint16 public constant MAX_KI_PROB = 1500;

    mapping(bytes32 => PricingResult) public acceptedPricings;
    mapping(bytes32 => bool) public pricingFulfilled;

    event PricingAccepted(bytes32 indexed noteId, uint16 putPremiumBps, uint16 kiProbabilityBps);

    error OnlyCRERouter();
    error PremiumOutOfBounds(uint16 premium);
    error KIProbabilityTooHigh(uint16 kiProb);
    error PricingAlreadyFulfilled(bytes32 noteId);

    constructor(address _creRouter, address _owner) Ownable(_owner) {
        creRouter = _creRouter;
    }

    modifier onlyCRERouter() {
        if (msg.sender != creRouter) revert OnlyCRERouter();
        _;
    }

    /// @inheritdoc ICREConsumer
    function fulfillPricing(bytes32 noteId, PricingResult calldata result) external onlyCRERouter {
        if (pricingFulfilled[noteId]) revert PricingAlreadyFulfilled(noteId);

        if (result.putPremiumBps < MIN_PREMIUM || result.putPremiumBps > MAX_PREMIUM) {
            revert PremiumOutOfBounds(result.putPremiumBps);
        }
        if (result.kiProbabilityBps > MAX_KI_PROB) {
            revert KIProbabilityTooHigh(result.kiProbabilityBps);
        }

        acceptedPricings[noteId] = result;
        pricingFulfilled[noteId] = true;

        emit PricingAccepted(noteId, result.putPremiumBps, result.kiProbabilityBps);
    }

    /// @inheritdoc ICREConsumer
    function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory) {
        return acceptedPricings[noteId];
    }

    /// @notice Check if pricing has been fulfilled for a note.
    function isPricingFulfilled(bytes32 noteId) external view returns (bool) {
        return pricingFulfilled[noteId];
    }
}
