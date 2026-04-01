# OptionPricer
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/pricing/OptionPricer.sol)

**Inherits:**
[IOptionPricer](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/IOptionPricer.sol/interface.IOptionPricer.md), Ownable

Analytical worst-of put approximation for on-chain verification.
Serves as a bound check -- rejects MC results that diverge too much.


## State Variables
### BPS

```solidity
uint256 public constant BPS = 10000;
```


### TOLERANCE_HIGH_VOL

```solidity
uint256 public constant TOLERANCE_HIGH_VOL = 300;
```


### TOLERANCE_MID_VOL

```solidity
uint256 public constant TOLERANCE_MID_VOL = 200;
```


### TOLERANCE_LOW_VOL

```solidity
uint256 public constant TOLERANCE_LOW_VOL = 150;
```


### MIN_PREMIUM

```solidity
uint256 public constant MIN_PREMIUM = 300;
```


### MAX_PREMIUM

```solidity
uint256 public constant MAX_PREMIUM = 1500;
```


### MAX_KI_PROB

```solidity
uint256 public constant MAX_KI_PROB = 1500;
```


### volOracle

```solidity
IVolOracle public volOracle;
```


## Functions
### constructor


```solidity
constructor(address _volOracle, address _owner) Ownable(_owner);
```

### verifyPricing


```solidity
function verifyPricing(PricingParams calldata params, uint256 mcPremiumBps, bytes32)
    external
    view
    returns (bool approved, uint256 onChainApprox);
```

### setVolOracle


```solidity
function setVolOracle(address _volOracle) external onlyOwner;
```

### _getAvgVol


```solidity
function _getAvgVol(address[] calldata basket) internal view returns (uint256);
```

### _getTolerance


```solidity
function _getTolerance(uint256 avgVol) internal pure returns (uint256);
```

### _bsApproxPut


```solidity
function _bsApproxPut(uint256 volBps, uint256 kiBarrierBps, uint256 T) internal pure returns (uint256);
```

### _sqrt


```solidity
function _sqrt(uint256 x) internal pure returns (uint256);
```

## Events
### VolOracleUpdated

```solidity
event VolOracleUpdated(address indexed newOracle);
```

