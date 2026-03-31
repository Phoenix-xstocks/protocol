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

    function getStreamedAmount(uint256 streamId) external view returns (uint256);
}
