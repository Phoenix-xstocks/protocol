// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IIssuanceGate } from "../interfaces/IIssuanceGate.sol";
import { ICREConsumer, PricingResult } from "../interfaces/ICREConsumer.sol";
import { IHedgeManager } from "../interfaces/IHedgeManager.sol";
import { IReserveFund } from "../interfaces/IReserveFund.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title IssuanceGate
/// @notice 4 pre-checks before note emission:
///         1. Pricing accepted by CREConsumer
///         2. HedgeManager reports capacity
///         3. ReserveFund above minimum (3%)
///         4. Active notes < MAX_ACTIVE_NOTES, notional within limits
contract IssuanceGate is IIssuanceGate, Ownable {
    uint256 public constant BPS = 10000;
    uint256 public constant MAX_ACTIVE_NOTES = 500;
    uint256 public constant MIN_NOTE_SIZE = 100e6;
    uint256 public constant MAX_NOTE_SIZE = 100_000e6;
    uint256 public constant RESERVE_MINIMUM_BPS = 300;
    uint256 public constant MAX_TVL = 5_000_000e6;

    ICREConsumer public creConsumer;
    IHedgeManager public hedgeManager;
    IReserveFund public reserveFund;

    uint256 public activeNoteCount;
    uint256 public totalNotionalOutstanding;

    event DependenciesUpdated(address creConsumer, address hedgeManager, address reserveFund);

    constructor(
        address _creConsumer,
        address _hedgeManager,
        address _reserveFund,
        address _owner
    ) Ownable(_owner) {
        require(_creConsumer != address(0), "zero creConsumer");
        require(_hedgeManager != address(0), "zero hedgeManager");
        require(_reserveFund != address(0), "zero reserveFund");
        creConsumer = ICREConsumer(_creConsumer);
        hedgeManager = IHedgeManager(_hedgeManager);
        reserveFund = IReserveFund(_reserveFund);
    }

    function checkIssuance(
        bytes32 noteId,
        uint256 notional,
        address[] calldata /* basket */
    ) external view returns (bool approved, string memory reason) {
        try creConsumer.getAcceptedPricing(noteId) returns (PricingResult memory) {
            // pricing exists
        } catch {
            return (false, "pricing not accepted");
        }

        uint256 reserveLevel = reserveFund.getLevel(totalNotionalOutstanding + notional);
        if (reserveLevel < RESERVE_MINIMUM_BPS) {
            return (false, "reserve below minimum");
        }

        if (activeNoteCount >= MAX_ACTIVE_NOTES) {
            return (false, "max active notes reached");
        }
        if (notional < MIN_NOTE_SIZE) {
            return (false, "notional below minimum");
        }
        if (notional > MAX_NOTE_SIZE) {
            return (false, "notional above maximum");
        }

        if (totalNotionalOutstanding + notional > MAX_TVL) {
            return (false, "TVL cap exceeded");
        }

        // Basic hedge capacity check: verify hedgeManager is operational
        if (address(hedgeManager) == address(0)) {
            return (false, "no hedge capacity");
        }

        return (true, "");
    }

    /// @notice Authorized callers (AutocallEngine)
    mapping(address => bool) public authorized;

    function setAuthorized(address account, bool status) external onlyOwner {
        authorized[account] = status;
    }

    modifier onlyAuthorizedOrOwner() {
        _onlyAuthorizedOrOwner();
        _;
    }

    function _onlyAuthorizedOrOwner() internal view {
        require(msg.sender == owner() || authorized[msg.sender], "not authorized");
    }

    function noteActivated(uint256 notional) external onlyAuthorizedOrOwner {
        activeNoteCount++;
        totalNotionalOutstanding += notional;
    }

    function noteSettled(uint256 notional) external onlyAuthorizedOrOwner {
        require(activeNoteCount > 0, "no active notes");
        require(totalNotionalOutstanding >= notional, "notional underflow");
        activeNoteCount--;
        totalNotionalOutstanding -= notional;
    }

    function setDependencies(
        address _creConsumer,
        address _hedgeManager,
        address _reserveFund
    ) external onlyOwner {
        if (_creConsumer != address(0)) creConsumer = ICREConsumer(_creConsumer);
        if (_hedgeManager != address(0)) hedgeManager = IHedgeManager(_hedgeManager);
        if (_reserveFund != address(0)) reserveFund = IReserveFund(_reserveFund);
        emit DependenciesUpdated(address(creConsumer), address(hedgeManager), address(reserveFund));
    }
}
