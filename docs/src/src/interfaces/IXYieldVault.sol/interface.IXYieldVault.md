# IXYieldVault
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/interfaces/IXYieldVault.sol)


## Functions
### requestDeposit


```solidity
function requestDeposit(uint256 amount, address receiver) external returns (uint256 requestId);
```

### claimDeposit


```solidity
function claimDeposit(uint256 requestId) external returns (uint256 noteTokenId);
```

### requestRedeem


```solidity
function requestRedeem(uint256 noteTokenId) external returns (uint256 requestId);
```

### claimRedeem


```solidity
function claimRedeem(uint256 requestId) external returns (uint256 amount);
```

### totalAssets


```solidity
function totalAssets() external view returns (uint256);
```

### maxDeposit


```solidity
function maxDeposit(address receiver) external view returns (uint256);
```

