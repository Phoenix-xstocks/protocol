// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISablierStream } from "../interfaces/ISablierStream.sol";

/// @title CouponStreamer
/// @notice Self-contained linear token streaming for coupon payments.
///         Replaces external Sablier V2 (not deployed on Ink). Each stream
///         linearly vests USDC from startTime to endTime. Holders call withdraw()
///         to claim; the owner (AutocallEngine) can cancel, returning unvested USDC.
contract CouponStreamer is ISablierStream, Ownable {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    struct Stream {
        address recipient;  // 20 bytes ┐
        bool canceled;      //  1 byte  │ slot 0 (31 bytes)
        uint40 startTime;   //  5 bytes │
        uint40 endTime;     //  5 bytes ┘
        uint128 deposit;    // 16 bytes ┐ slot 1 (32 bytes)
        uint128 withdrawn;  // 16 bytes ┘
    }

    // ----------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------

    IERC20 public immutable usdc;

    uint256 public nextStreamId;
    mapping(uint256 => Stream) public streams;
    mapping(bytes32 => uint256[]) internal _noteStreamIds;
    mapping(uint256 => bytes32) public streamToNote;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event CouponStreamStarted(bytes32 indexed noteId, address indexed holder, uint256 streamId, uint256 amount);
    event CouponStreamCancelled(bytes32 indexed noteId, uint256 indexed streamId, uint256 refundedAmount);
    event CouponWithdrawn(uint256 indexed streamId, address indexed recipient, uint256 amount);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error InvalidTimeRange();
    error ZeroAmount();
    error StreamNotFound(uint256 streamId);
    error StreamAlreadyCanceled(uint256 streamId);
    error NotRecipient();
    error NothingToWithdraw();

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor(address _usdc, address _owner) Ownable(_owner) {
        usdc = IERC20(_usdc);
        nextStreamId = 1; // stream IDs start at 1 (0 = invalid)
    }

    // ----------------------------------------------------------------
    // Owner functions (called by AutocallEngine)
    // ----------------------------------------------------------------

    /// @inheritdoc ISablierStream
    /// @dev Caller must approve this contract for `monthlyAmount` of USDC before calling.
    function startCouponStream(
        bytes32 noteId,
        address holder,
        uint256 monthlyAmount,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner returns (uint256 streamId) {
        if (endTime <= startTime) revert InvalidTimeRange();
        if (monthlyAmount == 0) revert ZeroAmount();

        // Pull USDC from caller (AutocallEngine)
        usdc.safeTransferFrom(msg.sender, address(this), monthlyAmount);

        streamId = nextStreamId++;

        streams[streamId] = Stream({
            recipient: holder,
            canceled: false,
            startTime: uint40(startTime),
            endTime: uint40(endTime),
            deposit: uint128(monthlyAmount),
            withdrawn: 0
        });

        _noteStreamIds[noteId].push(streamId);
        streamToNote[streamId] = noteId;

        emit CouponStreamStarted(noteId, holder, streamId, monthlyAmount);
    }

    /// @inheritdoc ISablierStream
    function cancelStream(uint256 streamId) external onlyOwner {
        bytes32 noteId = streamToNote[streamId];
        if (noteId == bytes32(0)) revert StreamNotFound(streamId);

        Stream storage s = streams[streamId];
        if (s.canceled) revert StreamAlreadyCanceled(streamId);

        s.canceled = true;

        uint256 vested = _vestedAmount(s);
        // Holder keeps max(vested, already withdrawn). Refund the rest.
        uint256 owed = vested > s.withdrawn ? vested : uint256(s.withdrawn);
        uint256 refunded = uint256(s.deposit) - owed;

        if (refunded > 0) {
            usdc.safeTransfer(msg.sender, refunded);
        }

        emit CouponStreamCancelled(noteId, streamId, refunded);
    }

    /// @inheritdoc ISablierStream
    function cancelAllNoteStreams(bytes32 noteId) external onlyOwner returns (uint256 totalRefunded) {
        uint256[] storage ids = _noteStreamIds[noteId];
        for (uint256 i = 0; i < ids.length; i++) {
            Stream storage s = streams[ids[i]];
            if (s.canceled) continue;

            s.canceled = true;

            uint256 vested = _vestedAmount(s);
            uint256 owed = vested > s.withdrawn ? vested : uint256(s.withdrawn);
            uint256 refunded = uint256(s.deposit) - owed;

            totalRefunded += refunded;
            emit CouponStreamCancelled(noteId, ids[i], refunded);
        }

        if (totalRefunded > 0) {
            usdc.safeTransfer(msg.sender, totalRefunded);
        }
    }

    // ----------------------------------------------------------------
    // Holder functions
    // ----------------------------------------------------------------

    /// @notice Withdraw vested USDC from a stream.
    function withdraw(uint256 streamId) external {
        Stream storage s = streams[streamId];
        if (msg.sender != s.recipient) revert NotRecipient();

        uint256 vested = _vestedAmount(s);
        uint256 withdrawable = vested - uint256(s.withdrawn);
        if (withdrawable == 0) revert NothingToWithdraw();

        s.withdrawn += uint128(withdrawable);
        usdc.safeTransfer(msg.sender, withdrawable);

        emit CouponWithdrawn(streamId, msg.sender, withdrawable);
    }

    // ----------------------------------------------------------------
    // View functions
    // ----------------------------------------------------------------

    /// @inheritdoc ISablierStream
    function getStreamedAmount(uint256 streamId) external view returns (uint256) {
        return _vestedAmount(streams[streamId]);
    }

    /// @inheritdoc ISablierStream
    function getNoteStreams(bytes32 noteId) external view returns (uint256[] memory) {
        return _noteStreamIds[noteId];
    }

    /// @notice Get full stream details.
    function getStream(uint256 streamId)
        external
        view
        returns (address recipient, uint128 deposit, uint40 startTime, uint40 endTime, uint128 withdrawn, bool canceled)
    {
        Stream storage s = streams[streamId];
        return (s.recipient, s.deposit, s.startTime, s.endTime, s.withdrawn, s.canceled);
    }

    /// @notice Get the amount a holder can withdraw right now.
    function getWithdrawable(uint256 streamId) external view returns (uint256) {
        Stream storage s = streams[streamId];
        return _vestedAmount(s) - uint256(s.withdrawn);
    }

    // ----------------------------------------------------------------
    // Admin
    // ----------------------------------------------------------------

    /// @notice Recover tokens sent to this contract by mistake.
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    // ----------------------------------------------------------------
    // Internal
    // ----------------------------------------------------------------

    /// @dev Linear vesting: deposit * elapsed / duration, clamped to [0, deposit].
    function _vestedAmount(Stream storage s) internal view returns (uint256) {
        if (block.timestamp <= s.startTime) return 0;
        if (block.timestamp >= s.endTime) return uint256(s.deposit);
        return (uint256(s.deposit) * (block.timestamp - s.startTime)) / (s.endTime - s.startTime);
    }
}
