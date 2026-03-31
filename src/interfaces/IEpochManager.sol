// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEpochManager {
    function getCurrentEpoch() external view returns (uint256);

    function getEpochStart(uint256 epochId) external view returns (uint256 timestamp);

    function advanceEpoch() external;

    function distributeWaterfall() external;

    function isEpochReady() external view returns (bool);
}
