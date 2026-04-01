// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ICREConsumer, PricingResult } from "../interfaces/ICREConsumer.sol";
import { IOptionPricer, PricingParams } from "../interfaces/IOptionPricer.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/// @notice Chainlink CRE IReceiver interface — consumer contracts must implement this.
///         The KeystoneForwarder calls onReport() after DON consensus.
interface IReceiver {
    function onReport(bytes calldata metadata, bytes calldata report) external;
}

/// @title CREConsumer
/// @notice Receives pricing results from Chainlink CRE workflow via the KeystoneForwarder.
///         Implements IReceiver + ERC165 for CRE compatibility. Performs bounds check and
///         cross-check against OptionPricer before accepting.
contract CREConsumer is ICREConsumer, IReceiver, ERC165, Ownable {
    uint256 public constant MIN_PREMIUM = 300;
    uint256 public constant MAX_PREMIUM = 1500;
    uint256 public constant MAX_KI_PROB = 1500;

    /// @notice Address of the Chainlink KeystoneForwarder (validates DON signatures).
    address public forwarder;
    IOptionPricer public optionPricer;

    /// @notice Optional: restrict to a specific CRE workflow owner address.
    address public expectedWorkflowOwner;

    mapping(bytes32 => PricingResult) public acceptedPricings;
    mapping(bytes32 => bool) public isPricingAccepted;
    mapping(bytes32 => PricingParams) internal noteParams;
    mapping(bytes32 => bool) public hasNoteParams;

    event PricingAccepted(bytes32 indexed noteId, uint16 putPremiumBps, uint16 kiProbabilityBps);
    event NoteParamsRegistered(bytes32 indexed noteId);
    event ForwarderUpdated(address indexed newForwarder);

    constructor(address _forwarder, address _optionPricer, address _owner) Ownable(_owner) {
        require(_forwarder != address(0), "zero forwarder");
        require(_optionPricer != address(0), "zero pricer");
        forwarder = _forwarder;
        optionPricer = IOptionPricer(_optionPricer);
    }

    // ---------------------------------------------------------------
    // IReceiver implementation (called by KeystoneForwarder)
    // ---------------------------------------------------------------

    /// @notice Called by the CRE KeystoneForwarder after DON consensus.
    ///         metadata = abi.encodePacked(bytes32 workflowId, bytes10 workflowName, address workflowOwner)
    ///         report   = abi.encode(bytes32 noteId, PricingResult result)
    function onReport(bytes calldata metadata, bytes calldata report) external override {
        require(msg.sender == forwarder, "only forwarder");

        // Optional: validate workflow owner from metadata (62 bytes = 32 + 10 + 20)
        if (expectedWorkflowOwner != address(0) && metadata.length >= 62) {
            address workflowOwner;
            assembly {
                // workflowOwner starts at byte 42 (32 + 10) in the packed metadata
                workflowOwner := shr(96, calldataload(add(metadata.offset, 42)))
            }
            require(workflowOwner == expectedWorkflowOwner, "unexpected workflow owner");
        }

        // Decode report payload
        (bytes32 noteId, PricingResult memory result) = abi.decode(report, (bytes32, PricingResult));

        _processPricing(noteId, result);
    }

    // ---------------------------------------------------------------
    // ERC165
    // ---------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || super.supportsInterface(interfaceId);
    }

    // ---------------------------------------------------------------
    // Note params registration (owner)
    // ---------------------------------------------------------------

    function registerNoteParams(bytes32 noteId, PricingParams calldata params) external onlyOwner {
        require(!hasNoteParams[noteId], "already registered");
        noteParams[noteId] = params;
        hasNoteParams[noteId] = true;
        emit NoteParamsRegistered(noteId);
    }

    // ---------------------------------------------------------------
    // Configuration (owner)
    // ---------------------------------------------------------------

    /// @notice Update the forwarder address (e.g. switching from simulation to production).
    function setForwarder(address _forwarder) external onlyOwner {
        require(_forwarder != address(0), "zero forwarder");
        forwarder = _forwarder;
        emit ForwarderUpdated(_forwarder);
    }

    /// @notice Restrict reports to a specific CRE workflow owner. Set address(0) to disable.
    function setExpectedWorkflowOwner(address _owner) external onlyOwner {
        expectedWorkflowOwner = _owner;
    }

    function setOptionPricer(address _optionPricer) external onlyOwner {
        require(_optionPricer != address(0), "zero address");
        optionPricer = IOptionPricer(_optionPricer);
    }

    // ---------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------

    function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory) {
        require(isPricingAccepted[noteId], "pricing not accepted");
        return acceptedPricings[noteId];
    }

    function getNoteParams(bytes32 noteId) external view returns (PricingParams memory) {
        require(hasNoteParams[noteId], "not registered");
        return noteParams[noteId];
    }

    // ---------------------------------------------------------------
    // Internal: validate + store pricing
    // ---------------------------------------------------------------

    function _processPricing(bytes32 noteId, PricingResult memory result) internal {
        require(hasNoteParams[noteId], "note not registered");
        require(!isPricingAccepted[noteId], "already accepted");

        require(result.putPremiumBps >= MIN_PREMIUM, "premium too low");
        require(result.putPremiumBps <= MAX_PREMIUM, "premium too high");
        require(result.kiProbabilityBps <= MAX_KI_PROB, "KI prob too high");

        PricingParams storage params = noteParams[noteId];
        (bool approved,) = optionPricer.verifyPricing(params, uint256(result.putPremiumBps), result.inputsHash);
        require(approved, "CRE vs on-chain divergence");

        acceptedPricings[noteId] = result;
        isPricingAccepted[noteId] = true;

        emit PricingAccepted(noteId, result.putPremiumBps, result.kiProbabilityBps);
    }
}
