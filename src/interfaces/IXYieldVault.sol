// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IXYieldVault {
    function requestDeposit(uint256 amount, address receiver) external returns (uint256 requestId);

    function claimDeposit(uint256 requestId) external returns (uint256 noteTokenId);

    function requestRedeem(uint256 noteTokenId) external returns (uint256 requestId);

    function claimRedeem(uint256 requestId) external returns (uint256 amount);

    function totalAssets() external view returns (uint256);

    function maxDeposit(address receiver) external view returns (uint256);
}
