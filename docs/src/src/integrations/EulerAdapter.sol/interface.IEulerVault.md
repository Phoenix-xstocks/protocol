# IEulerVault
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/EulerAdapter.sol)

Minimal ERC-4626 interface for Euler V2 vaults


## Functions
### deposit


```solidity
function deposit(uint256 assets, address receiver) external returns (uint256 shares);
```

### withdraw


```solidity
function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
```

### redeem


```solidity
function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
```

### balanceOf


```solidity
function balanceOf(address account) external view returns (uint256);
```

### convertToAssets


```solidity
function convertToAssets(uint256 shares) external view returns (uint256);
```

### convertToShares


```solidity
function convertToShares(uint256 assets) external view returns (uint256);
```

### totalAssets


```solidity
function totalAssets() external view returns (uint256);
```

### asset


```solidity
function asset() external view returns (address);
```

### maxDeposit


```solidity
function maxDeposit(address) external view returns (uint256);
```

