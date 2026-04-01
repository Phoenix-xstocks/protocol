# VolOracle
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/pricing/VolOracle.sol)

**Inherits:**
[IVolOracle](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IVolOracle.sol/interface.IVolOracle.md), [IReceiver](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/pricing/CREConsumer.sol/interface.IReceiver.md), ERC165, AccessControl

Stores implied volatilities and pairwise correlations for xStocks basket assets.
Updated by Chainlink CRE workflow ("xYield-VolOracle") via KeystoneForwarder,
or manually by UPDATER_ROLE. Falls back to admin-set vols when data is stale.


## State Variables
### UPDATER_ROLE

```solidity
bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
```


### forwarder
Address of the Chainlink KeystoneForwarder (validates DON signatures).


```solidity
address public forwarder;
```


### vols

```solidity
mapping(address => uint256) public vols;
```


### correlations

```solidity
mapping(bytes32 => uint256) public correlations;
```


### trackedAssets

```solidity
address[] public trackedAssets;
```


### isTracked

```solidity
mapping(address => bool) public isTracked;
```


### lastUpdate

```solidity
uint256 public lastUpdate;
```


### stalenessThreshold

```solidity
uint256 public stalenessThreshold = 2 hours;
```


### fallbackVols

```solidity
mapping(address => uint256) public fallbackVols;
```


### fallbackCorrelations

```solidity
mapping(bytes32 => uint256) public fallbackCorrelations;
```


## Functions
### constructor


```solidity
constructor(address admin, address _forwarder);
```

### onReport

Called by the CRE KeystoneForwarder after DON consensus.
report = abi.encode(address[] assets, uint256[] volsBps, uint256[] correlationsBps)


```solidity
function onReport(bytes calldata, bytes calldata report) external override;
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public view override(ERC165, AccessControl) returns (bool);
```

### updateVols


```solidity
function updateVols(address[] calldata assets, uint256[] calldata volsBps, uint256[] calldata correlationsBps)
    external
    onlyRole(UPDATER_ROLE);
```

### getVol


```solidity
function getVol(address asset) external view returns (uint256 volBps);
```

### getAvgCorrelation


```solidity
function getAvgCorrelation(address[] calldata basket) external view returns (uint256 avgCorrBps);
```

### getLastUpdate


```solidity
function getLastUpdate() external view returns (uint256 timestamp);
```

### setForwarder


```solidity
function setForwarder(address _forwarder) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### setFallbackVol


```solidity
function setFallbackVol(address asset, uint256 volBps) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### setFallbackCorrelation


```solidity
function setFallbackCorrelation(address asset1, address asset2, uint256 corrBps)
    external
    onlyRole(DEFAULT_ADMIN_ROLE);
```

### setStalenessThreshold


```solidity
function setStalenessThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### _updateVols


```solidity
function _updateVols(address[] memory assets, uint256[] memory volsBps, uint256[] memory correlationsBps) internal;
```

### _pairKey


```solidity
function _pairKey(address a, address b) internal pure returns (bytes32);
```

### _isStale


```solidity
function _isStale() internal view returns (bool);
```

## Events
### VolsUpdated

```solidity
event VolsUpdated(address[] assets, uint256[] volsBps, uint256[] correlationsBps, uint256 timestamp);
```

### FallbackVolSet

```solidity
event FallbackVolSet(address asset, uint256 volBps);
```

### StalenessThresholdUpdated

```solidity
event StalenessThresholdUpdated(uint256 newThreshold);
```

### ForwarderUpdated

```solidity
event ForwarderUpdated(address indexed newForwarder);
```

