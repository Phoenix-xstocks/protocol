// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISablierStream {
    function startCouponStream(
        bytes32 noteId,
        address holder,
        uint256 monthlyAmount,
        uint256 startTime,
        uint256 endTime
    ) external returns (uint256 streamId);

    function cancelStream(uint256 streamId) external;

    function cancelAllNoteStreams(bytes32 noteId) external returns (uint256 totalRefunded);

    function getStreamedAmount(uint256 streamId) external view returns (uint256);

    function getNoteStreams(bytes32 noteId) external view returns (uint256[] memory);
}
