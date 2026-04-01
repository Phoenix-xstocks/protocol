# ICarryEngine
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/ICarryEngine.sol)


## Functions
### collectCarry


```solidity
function collectCarry(bytes32 noteId) external returns (uint256 fundingCarry, uint256 lendingCarry);
```

### getTotalCarryRate


```solidity
function getTotalCarryRate() external view returns (uint256 rateBps);
```

### getFundingRate


```solidity
function getFundingRate() external view returns (uint256 rateBps);
```

### getLendingRate


```solidity
function getLendingRate() external view returns (uint256 rateBps);
```

