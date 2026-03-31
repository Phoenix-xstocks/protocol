// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ICREConsumer, PricingResult } from "../interfaces/ICREConsumer.sol";
import { IOptionPricer, PricingParams } from "../interfaces/IOptionPricer.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CREConsumer
/// @notice Receives pricing results from Chainlink CRE workflow after DON consensus.
///         Performs bounds check and cross-check against OptionPricer before accepting.
contract CREConsumer is ICREConsumer, Ownable {
    uint256 public constant MIN_PREMIUM = 300;
    uint256 public constant MAX_PREMIUM = 1500;
    uint256 public constant MAX_KI_PROB = 1500;

    address public immutable creRouter;
    IOptionPricer public optionPricer;

    mapping(bytes32 => PricingResult) public acceptedPricings;
    mapping(bytes32 => bool) public isPricingAccepted;
    mapping(bytes32 => PricingParams) internal noteParams;
    mapping(bytes32 => bool) public hasNoteParams;

    event PricingAccepted(bytes32 indexed noteId, uint16 putPremiumBps, uint16 kiProbabilityBps);
    event PricingRejected(bytes32 indexed noteId, string reason);
    event NoteParamsRegistered(bytes32 indexed noteId);

    modifier onlyCRERouter() {
        require(msg.sender == creRouter, "only CRE router");
        _;
    }

    constructor(address _creRouter, address _optionPricer, address _owner) Ownable(_owner) {
        require(_creRouter != address(0), "zero router");
        require(_optionPricer != address(0), "zero pricer");
        creRouter = _creRouter;
        optionPricer = IOptionPricer(_optionPricer);
    }

    function registerNoteParams(bytes32 noteId, PricingParams calldata params) external onlyOwner {
        require(!hasNoteParams[noteId], "already registered");
        noteParams[noteId] = params;
        hasNoteParams[noteId] = true;
        emit NoteParamsRegistered(noteId);
    }

    function fulfillPricing(bytes32 noteId, PricingResult calldata result) external onlyCRERouter {
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

    function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory) {
        require(isPricingAccepted[noteId], "pricing not accepted");
        return acceptedPricings[noteId];
    }

    function setOptionPricer(address _optionPricer) external onlyOwner {
        require(_optionPricer != address(0), "zero address");
        optionPricer = IOptionPricer(_optionPricer);
    }

    function getNoteParams(bytes32 noteId) external view returns (PricingParams memory) {
        require(hasNoteParams[noteId], "not registered");
        return noteParams[noteId];
    }
}
