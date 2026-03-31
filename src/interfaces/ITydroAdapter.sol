// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITydroAdapter {
    function depositCollateral(address asset, uint256 amount) external;

    function withdrawCollateral(address asset) external returns (uint256 amount);

    function borrowUSDC(uint256 amount) external returns (uint256 borrowed);

    function repayUSDC(uint256 amount) external;

    function getCollateralValue(address asset) external view returns (uint256);

    function getLendingRate() external view returns (uint256 ratePerSecond);

    function depositUSDC(uint256 amount) external;

    function withdrawUSDC(uint256 amount) external returns (uint256 withdrawn);
}
