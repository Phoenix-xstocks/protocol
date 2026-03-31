// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReserveFund {
    function deposit(uint256 amount) external;

    function coverDeficit(uint256 amount) external returns (uint256 covered);

    function getBalance() external view returns (uint256);

    function getLevel(uint256 totalNotional) external view returns (uint256 levelBps);

    function getHaircutRatio(uint256 totalNotional) external view returns (uint256 ratioBps);
}
