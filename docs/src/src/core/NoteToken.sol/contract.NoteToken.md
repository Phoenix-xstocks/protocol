# NoteToken
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/core/NoteToken.sol)

**Inherits:**
ERC1155, AccessControl

ERC-1155 soulbound token representing Phoenix Autocall note positions.
tokenId = uint256(noteId). Non-transferable in Phase 1.


## State Variables
### MINTER_ROLE

```solidity
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
```


### BURNER_ROLE

```solidity
bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
```


### noteHolder
*noteId -> holder address (single holder per note in Phase 1)*


```solidity
mapping(uint256 => address) public noteHolder;
```


## Functions
### constructor


```solidity
constructor(address admin) ERC1155("");
```

### mint

Mint note tokens on claimDeposit


```solidity
function mint(address to, bytes32 noteId, uint256 amount) external onlyRole(MINTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|The holder address|
|`noteId`|`bytes32`|The note identifier|
|`amount`|`uint256`|The notional amount (1 token = 1 USDC unit)|


### burn

Burn note tokens on settlement


```solidity
function burn(address from, bytes32 noteId, uint256 amount) external onlyRole(BURNER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|The holder address|
|`noteId`|`bytes32`|The note identifier|
|`amount`|`uint256`|The amount to burn|


### holderOf

Returns the holder of a note


```solidity
function holderOf(bytes32 noteId) external view returns (address);
```

### _update


```solidity
function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override;
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool);
```

## Events
### NoteMinted

```solidity
event NoteMinted(bytes32 indexed noteId, address indexed holder, uint256 amount);
```

### NoteBurned

```solidity
event NoteBurned(bytes32 indexed noteId, address indexed holder, uint256 amount);
```

## Errors
### TransferDisabled

```solidity
error TransferDisabled();
```

### ZeroAddress

```solidity
error ZeroAddress();
```

