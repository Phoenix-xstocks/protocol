// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFeeCollector {
    function collectEmbeddedFee(uint256 notional) external returns (uint256 fee);

    function collectOriginationFee(uint256 notional) external returns (uint256 fee);

    function collectManagementFee(uint256 notional, uint256 elapsed) external returns (uint256 fee);

    function collectPerformanceFee(uint256 carryNet) external returns (uint256 fee);

    function getTotalCollected() external view returns (uint256);

    function treasury() external view returns (address);
}
