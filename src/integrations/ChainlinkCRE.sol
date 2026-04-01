// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { ICREConsumer, PricingResult } from "../interfaces/ICREConsumer.sol";
import { IOptionPricer, PricingParams } from "../interfaces/IOptionPricer.sol";
import { IReceiver } from "../pricing/CREConsumer.sol";

/// @title ChainlinkCRE
/// @notice Alternative CRE consumer implementation using custom errors.
///         Implements IReceiver for CRE KeystoneForwarder compatibility.
contract ChainlinkCRE is ICREConsumer, IReceiver, ERC165, Ownable {
    address public forwarder;
    IOptionPricer public optionPricer;

    uint16 public constant MIN_PREMIUM = 300;
    uint16 public constant MAX_PREMIUM = 1500;
    uint16 public constant MAX_KI_PROB = 1500;

    mapping(bytes32 => PricingResult) public acceptedPricings;
    mapping(bytes32 => bool) public pricingFulfilled;
    mapping(bytes32 => PricingParams) internal pricingParams;

    event PricingRequested(bytes32 indexed noteId);
    event PricingAccepted(bytes32 indexed noteId, uint16 putPremiumBps, uint16 kiProbabilityBps);
    event ForwarderUpdated(address indexed newForwarder);

    error OnlyForwarder();
    error PremiumOutOfBounds(uint16 premium);
    error KIProbabilityTooHigh(uint16 kiProb);
    error PricingAlreadyFulfilled(bytes32 noteId);
    error PricingCrossCheckFailed(bytes32 noteId);
    error NoteNotRegistered(bytes32 noteId);

    constructor(address _forwarder, address _optionPricer, address _owner) Ownable(_owner) {
        require(_optionPricer != address(0), "zero optionPricer");
        require(_forwarder != address(0), "zero forwarder");
        forwarder = _forwarder;
        optionPricer = IOptionPricer(_optionPricer);
    }

    // ---------------------------------------------------------------
    // IReceiver implementation (called by KeystoneForwarder)
    // ---------------------------------------------------------------

    /// @notice Called by the CRE KeystoneForwarder after DON consensus.
    function onReport(bytes calldata, bytes calldata report) external override {
        if (msg.sender != forwarder) revert OnlyForwarder();

        (bytes32 noteId, PricingResult memory result) = abi.decode(report, (bytes32, PricingResult));
        _processPricing(noteId, result);
    }

    // ---------------------------------------------------------------
    // ERC165
    // ---------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Submit pricing params before CRE fulfillment (for cross-check)
    function requestPricing(bytes32 noteId, PricingParams calldata params) external onlyOwner {
        pricingParams[noteId] = params;
        emit PricingRequested(noteId);
    }

    /// @notice Update the forwarder address.
    function setForwarder(address _forwarder) external onlyOwner {
        require(_forwarder != address(0), "zero forwarder");
        forwarder = _forwarder;
        emit ForwarderUpdated(_forwarder);
    }

    /// @inheritdoc ICREConsumer
    function registerNoteParams(bytes32 noteId, PricingParams calldata params) external override {
        pricingParams[noteId] = params;
        emit PricingRequested(noteId);
    }

    /// @inheritdoc ICREConsumer
    function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory) {
        return acceptedPricings[noteId];
    }

    /// @notice Check if pricing has been fulfilled for a note.
    function isPricingFulfilled(bytes32 noteId) external view returns (bool) {
        return pricingFulfilled[noteId];
    }

    // ---------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------

    function _processPricing(bytes32 noteId, PricingResult memory result) internal {
        if (pricingFulfilled[noteId]) revert PricingAlreadyFulfilled(noteId);

        PricingParams storage params = pricingParams[noteId];
        if (params.basket.length == 0) revert NoteNotRegistered(noteId);

        if (result.putPremiumBps < MIN_PREMIUM || result.putPremiumBps > MAX_PREMIUM) {
            revert PremiumOutOfBounds(result.putPremiumBps);
        }
        if (result.kiProbabilityBps > MAX_KI_PROB) {
            revert KIProbabilityTooHigh(result.kiProbabilityBps);
        }

        (bool approved, ) = optionPricer.verifyPricing(
            params,
            result.putPremiumBps,
            result.inputsHash
        );
        if (!approved) revert PricingCrossCheckFailed(noteId);

        acceptedPricings[noteId] = result;
        pricingFulfilled[noteId] = true;

        emit PricingAccepted(noteId, result.putPremiumBps, result.kiProbabilityBps);
    }
}
