// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISablierStream } from "../interfaces/ISablierStream.sol";

/// @notice Minimal interface for Sablier V2 LockupLinear operations.
interface ISablierLockupMinimal {
    struct Timestamps {
        uint40 start;
        uint40 end;
    }

    struct CreateWithTimestamps {
        address sender;
        address recipient;
        uint128 depositAmount;
        IERC20 token;
        bool cancelable;
        bool transferable;
        Timestamps timestamps;
        string shape;
    }

    struct UnlockAmounts {
        uint128 start;
        uint128 cliff;
    }

    function createWithTimestampsLL(
        CreateWithTimestamps calldata params,
        UnlockAmounts calldata unlockAmounts,
        uint40 granularity,
        uint40 cliffTime
    ) external payable returns (uint256 streamId);

    function cancel(uint256 streamId) external payable returns (uint128 refundedAmount);

    function streamedAmountOf(uint256 streamId) external view returns (uint128 streamedAmount);
}

/// @title SablierStream
/// @notice Coupon streaming via Sablier V2 LockupLinear. Creates real-time coupon streams for note holders.
contract SablierStream is ISablierStream, Ownable {
    using SafeERC20 for IERC20;

    ISablierLockupMinimal public immutable sablier;
    IERC20 public immutable usdc;

    mapping(bytes32 => uint256[]) public noteStreamIds;
    mapping(uint256 => bytes32) public streamToNote;

    event CouponStreamStarted(bytes32 indexed noteId, address indexed holder, uint256 streamId, uint256 monthlyAmount);
    event CouponStreamCancelled(uint256 indexed streamId);

    error InvalidTimeRange();
    error ZeroAmount();
    error StreamNotFound(uint256 streamId);

    constructor(address _sablier, address _usdc, address _owner) Ownable(_owner) {
        sablier = ISablierLockupMinimal(_sablier);
        usdc = IERC20(_usdc);
    }

    /// @inheritdoc ISablierStream
    function startCouponStream(
        bytes32 noteId,
        address holder,
        uint256 monthlyAmount,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner returns (uint256 streamId) {
        if (endTime <= startTime) revert InvalidTimeRange();
        if (monthlyAmount == 0) revert ZeroAmount();

        usdc.forceApprove(address(sablier), monthlyAmount);

        ISablierLockupMinimal.CreateWithTimestamps memory params = ISablierLockupMinimal.CreateWithTimestamps({
            sender: address(this),
            recipient: holder,
            depositAmount: uint128(monthlyAmount),
            token: usdc,
            cancelable: true,
            transferable: false,
            timestamps: ISablierLockupMinimal.Timestamps({ start: uint40(startTime), end: uint40(endTime) }),
            shape: ""
        });

        ISablierLockupMinimal.UnlockAmounts memory unlockAmounts =
            ISablierLockupMinimal.UnlockAmounts({ start: 0, cliff: 0 });

        streamId = sablier.createWithTimestampsLL(params, unlockAmounts, 0, 0);

        noteStreamIds[noteId].push(streamId);
        streamToNote[streamId] = noteId;

        emit CouponStreamStarted(noteId, holder, streamId, monthlyAmount);
    }

    /// @inheritdoc ISablierStream
    function cancelStream(uint256 streamId) external onlyOwner {
        bytes32 noteId = streamToNote[streamId];
        if (noteId == bytes32(0)) revert StreamNotFound(streamId);

        sablier.cancel(streamId);

        emit CouponStreamCancelled(streamId);
    }

    /// @inheritdoc ISablierStream
    function getStreamedAmount(uint256 streamId) external view returns (uint256) {
        return uint256(sablier.streamedAmountOf(streamId));
    }

    /// @notice Get all stream IDs for a note.
    function getNoteStreams(bytes32 noteId) external view returns (uint256[] memory) {
        return noteStreamIds[noteId];
    }

    /// @notice Recover tokens sent to this contract by mistake.
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
