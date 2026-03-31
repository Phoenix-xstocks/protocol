// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVolOracle {
    function updateVols(
        address[] calldata assets,
        uint256[] calldata volsBps,
        uint256[] calldata correlationsBps
    ) external;

    function getVol(address asset) external view returns (uint256 volBps);

    function getAvgCorrelation(address[] calldata basket) external view returns (uint256 avgCorrBps);

    function getLastUpdate() external view returns (uint256 timestamp);
}
