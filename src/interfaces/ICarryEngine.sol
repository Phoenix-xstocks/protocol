// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICarryEngine {
    function collectCarry(bytes32 noteId) external returns (uint256 fundingCarry, uint256 lendingCarry);

    function getTotalCarryRate() external view returns (uint256 rateBps);

    function getFundingRate() external view returns (uint256 rateBps);

    function getLendingRate() external view returns (uint256 rateBps);
}
