// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ICREConsumer, PricingResult } from "../interfaces/ICREConsumer.sol";
import { IOptionPricer, PricingParams } from "../interfaces/IOptionPricer.sol";

/// @title ChainlinkCRE
/// @notice CRE workflows consumer for pricing oracle. Receives fulfillment callbacks
///         from the Chainlink CRE Router after DON consensus on Monte Carlo pricing.
contract ChainlinkCRE is ICREConsumer, Ownable {
    address public immutable creRouter;
    IOptionPricer public optionPricer;

    uint16 public constant MIN_PREMIUM = 300;
    uint16 public constant MAX_PREMIUM = 1500;
    uint16 public constant MAX_KI_PROB = 1500;

    mapping(bytes32 => PricingResult) public acceptedPricings;
    mapping(bytes32 => bool) public pricingFulfilled;
    mapping(bytes32 => PricingParams) internal pricingParams;

    event PricingRequested(bytes32 indexed noteId);
    event PricingAccepted(bytes32 indexed noteId, uint16 putPremiumBps, uint16 kiProbabilityBps);

    error OnlyCRERouter();
    error PremiumOutOfBounds(uint16 premium);
    error KIProbabilityTooHigh(uint16 kiProb);
    error PricingAlreadyFulfilled(bytes32 noteId);
    error PricingCrossCheckFailed(bytes32 noteId);

    constructor(address _creRouter, address _optionPricer, address _owner) Ownable(_owner) {
        require(_optionPricer != address(0), "zero optionPricer");
        creRouter = _creRouter;
        optionPricer = IOptionPricer(_optionPricer);
    }

    modifier onlyCRERouter() {
        if (msg.sender != creRouter) revert OnlyCRERouter();
        _;
    }

    /// @notice Submit pricing params before CRE fulfillment (for cross-check)
    function requestPricing(bytes32 noteId, PricingParams calldata params) external onlyOwner {
        pricingParams[noteId] = params;
        emit PricingRequested(noteId);
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

        // Cross-check with on-chain OptionPricer (spec 4.2)
        PricingParams storage params = pricingParams[noteId];
        if (params.basket.length > 0) {
            (bool approved, ) = optionPricer.verifyPricing(
                params,
                result.putPremiumBps,
                result.inputsHash
            );
            if (!approved) revert PricingCrossCheckFailed(noteId);
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
