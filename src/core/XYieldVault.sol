// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IXYieldVault } from "../interfaces/IXYieldVault.sol";
import { IAutocallEngine } from "../interfaces/IAutocallEngine.sol";
import { IFeeCollector } from "../interfaces/IFeeCollector.sol";
import { NoteToken } from "./NoteToken.sol";

/// @title XYieldVault
/// @notice ERC-7540 async vault for Phoenix Autocall deposits.
///         requestDeposit -> pricing -> hedge -> claimDeposit -> NoteToken minted.
///         24h max delay, auto-refund if not claimed in time.
contract XYieldVault is IXYieldVault, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Roles
    // ----------------------------------------------------------------
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------
    uint256 public constant MIN_NOTE_SIZE = 100e6; // $100 in USDC (6 decimals)
    uint256 public constant MAX_NOTE_SIZE = 100_000e6; // $100k
    uint256 public constant MAX_TVL = 5_000_000e6; // $5M
    uint256 public constant MAX_ACTIVE_NOTES = 500;
    uint256 public constant CLAIM_DEADLINE = 24 hours;

    // ----------------------------------------------------------------
    // Request status
    // ----------------------------------------------------------------
    enum RequestStatus {
        Pending,
        ReadyToClaim,
        Claimed,
        Refunded,
        Cancelled
    }

    struct DepositRequest {
        address depositor;
        address receiver;
        uint256 amount;
        address[] basket;
        bytes32 noteId;
        uint256 requestedAt;
        uint256 readyAt;
        RequestStatus status;
    }

    // ----------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------
    IERC20 public immutable USDC;
    IAutocallEngine public immutable ENGINE;
    NoteToken public immutable NOTE_TOKEN;
    IFeeCollector public feeCollector;

    mapping(uint256 => DepositRequest) public requests;
    uint256 public nextRequestId;
    uint256 public activeNoteCount;
    uint256 private _totalAssets;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------
    event DepositRequested(uint256 indexed requestId, address indexed depositor, uint256 amount);
    event DepositReadyToClaim(uint256 indexed requestId, bytes32 indexed noteId);
    event DepositClaimed(uint256 indexed requestId, bytes32 indexed noteId, uint256 tokenId);
    event DepositRefunded(uint256 indexed requestId, address indexed depositor, uint256 amount);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------
    error BelowMinDeposit();
    error AboveMaxDeposit();
    error TVLExceeded();
    error MaxNotesExceeded();
    error InvalidRequestStatus();
    error NotReceiver();
    error ClaimDeadlineNotReached();
    error ClaimDeadlinePassed();
    error ZeroAmount();

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------
    constructor(address admin, address _usdc, address _engine, address _noteToken) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        USDC = IERC20(_usdc);
        ENGINE = IAutocallEngine(_engine);
        NOTE_TOKEN = NoteToken(_noteToken);
    }

    /// @notice Set the fee collector. Admin only.
    function setFeeCollector(address _feeCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeCollector = IFeeCollector(_feeCollector);
    }

    // ----------------------------------------------------------------
    // Deposit flow
    // ----------------------------------------------------------------

    /// @inheritdoc IXYieldVault
    function requestDeposit(uint256 amount, address receiver)
        external
        override
        nonReentrant
        returns (uint256 requestId)
    {
        requestId = _requestDeposit(amount, receiver, new address[](0));
    }

    /// @notice Request deposit with basket preference. User chooses their xStocks.
    function requestDepositWithBasket(uint256 amount, address receiver, address[] calldata basket)
        external
        nonReentrant
        returns (uint256 requestId)
    {
        require(basket.length >= 2 && basket.length <= 5, "invalid basket size");
        requestId = _requestDeposit(amount, receiver, basket);
    }

    function _requestDeposit(uint256 amount, address receiver, address[] memory basket)
        internal
        returns (uint256 requestId)
    {
        if (amount == 0) revert ZeroAmount();
        if (amount < MIN_NOTE_SIZE) revert BelowMinDeposit();
        if (amount > MAX_NOTE_SIZE) revert AboveMaxDeposit();
        if (_totalAssets + amount > MAX_TVL) revert TVLExceeded();
        if (activeNoteCount >= MAX_ACTIVE_NOTES) revert MaxNotesExceeded();

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        requestId = nextRequestId++;
        DepositRequest storage req = requests[requestId];
        req.depositor = msg.sender;
        req.receiver = receiver;
        req.amount = amount;
        req.basket = basket; // user's basket preference (empty = operator chooses)
        req.requestedAt = block.timestamp;
        req.status = RequestStatus.Pending;

        emit DepositRequested(requestId, msg.sender, amount);
    }

    /// @notice Operator marks request as ready after pricing + hedge opened
    function fulfillDeposit(uint256 requestId, bytes32 noteId, address[] calldata basket)
        external
        onlyRole(OPERATOR_ROLE)
    {
        DepositRequest storage req = requests[requestId];
        if (req.status != RequestStatus.Pending) revert InvalidRequestStatus();

        req.noteId = noteId;
        req.basket = basket;
        req.readyAt = block.timestamp;
        req.status = RequestStatus.ReadyToClaim;

        emit DepositReadyToClaim(requestId, noteId);
    }

    /// @inheritdoc IXYieldVault
    function claimDeposit(uint256 requestId) external override nonReentrant returns (uint256 noteTokenId) {
        DepositRequest storage req = requests[requestId];
        if (req.status != RequestStatus.ReadyToClaim) revert InvalidRequestStatus();
        if (msg.sender != req.receiver) revert NotReceiver();

        // Check 24h deadline from readyAt
        if (block.timestamp > req.readyAt + CLAIM_DEADLINE) revert ClaimDeadlinePassed();

        req.status = RequestStatus.Claimed;
        noteTokenId = uint256(req.noteId);

        // Collect deposit fees (embedded 0.5% + origination 0.1%) per spec section 13/17
        uint256 netAmount = req.amount;
        if (address(feeCollector) != address(0)) {
            uint256 embeddedFee = (req.amount * 50) / 10000; // 0.5%
            uint256 originationFee = (req.amount * 10) / 10000; // 0.1%
            uint256 totalFees = embeddedFee + originationFee;
            if (totalFees > 0) {
                USDC.safeTransfer(feeCollector.treasury(), totalFees);
                netAmount -= totalFees;
            }
        }

        // Mint NoteToken for net amount (what the engine actually receives)
        NOTE_TOKEN.mint(req.receiver, req.noteId, netAmount);

        // Transfer net USDC to engine for coupon payments and settlement
        USDC.safeTransfer(address(ENGINE), netAmount);

        _totalAssets += req.amount;
        activeNoteCount++;

        emit DepositClaimed(requestId, req.noteId, noteTokenId);
    }

    /// @notice Auto-refund if claim deadline passed
    function refundDeposit(uint256 requestId) external nonReentrant {
        DepositRequest storage req = requests[requestId];
        if (req.status == RequestStatus.Pending) {
            // Pending requests can be refunded after 24h from request time
            if (block.timestamp < req.requestedAt + CLAIM_DEADLINE) revert ClaimDeadlineNotReached();
        } else if (req.status == RequestStatus.ReadyToClaim) {
            // Ready requests can be refunded after 24h from ready time
            if (block.timestamp < req.readyAt + CLAIM_DEADLINE) revert ClaimDeadlineNotReached();
        } else {
            revert InvalidRequestStatus();
        }

        req.status = RequestStatus.Refunded;
        USDC.safeTransfer(req.depositor, req.amount);

        emit DepositRefunded(requestId, req.depositor, req.amount);
    }

    // ----------------------------------------------------------------
    // Redeem (placeholder -- settlement handled by AutocallEngine)
    // ----------------------------------------------------------------

    /// @inheritdoc IXYieldVault
    function requestRedeem(uint256 /* noteTokenId */ ) external pure override returns (uint256) {
        // Redemption is handled through the AutocallEngine settlement flow
        revert("Redeem via AutocallEngine.settleKi");
    }

    /// @inheritdoc IXYieldVault
    function claimRedeem(uint256 /* requestId */ ) external pure override returns (uint256) {
        revert("Redeem via AutocallEngine settlement");
    }

    // ----------------------------------------------------------------
    // Accounting
    // ----------------------------------------------------------------

    /// @notice Called by engine/operator when a note settles to update accounting
    function noteSettled(uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (amount <= _totalAssets) {
            _totalAssets -= amount;
        } else {
            _totalAssets = 0;
        }
        if (activeNoteCount > 0) {
            activeNoteCount--;
        }
    }

    /// @inheritdoc IXYieldVault
    function totalAssets() external view override returns (uint256) {
        return _totalAssets;
    }

    /// @inheritdoc IXYieldVault
    function maxDeposit(address /* receiver */ ) external view override returns (uint256) {
        uint256 remaining = MAX_TVL > _totalAssets ? MAX_TVL - _totalAssets : 0;
        uint256 noteLimit = MAX_NOTE_SIZE;
        return remaining < noteLimit ? remaining : noteLimit;
    }
}
