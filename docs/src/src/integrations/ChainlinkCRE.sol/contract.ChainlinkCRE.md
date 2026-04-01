# ChainlinkCRE
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/integrations/ChainlinkCRE.sol)

**Inherits:**
[ICREConsumer](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/ICREConsumer.sol/interface.ICREConsumer.md), [IReceiver](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/pricing/CREConsumer.sol/interface.IReceiver.md), ERC165, Ownable

Alternative CRE consumer implementation using custom errors.
Implements IReceiver for CRE KeystoneForwarder compatibility.


## State Variables
### forwarder

```solidity
address public forwarder;
```


### optionPricer

```solidity
IOptionPricer public optionPricer;
```


### MIN_PREMIUM

```solidity
uint16 public constant MIN_PREMIUM = 300;
```


### MAX_PREMIUM

```solidity
uint16 public constant MAX_PREMIUM = 1500;
```


### MAX_KI_PROB

```solidity
uint16 public constant MAX_KI_PROB = 1500;
```


### acceptedPricings

```solidity
mapping(bytes32 => PricingResult) public acceptedPricings;
```


### pricingFulfilled

```solidity
mapping(bytes32 => bool) public pricingFulfilled;
```


### pricingParams

```solidity
mapping(bytes32 => PricingParams) internal pricingParams;
```


## Functions
### constructor


```solidity
constructor(address _forwarder, address _optionPricer, address _owner) Ownable(_owner);
```

### onReport

Called by the CRE KeystoneForwarder after DON consensus.


```solidity
function onReport(bytes calldata, bytes calldata report) external override;
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public view override returns (bool);
```

### requestPricing

Submit pricing params before CRE fulfillment (for cross-check)


```solidity
function requestPricing(bytes32 noteId, PricingParams calldata params) external onlyOwner;
```

### setForwarder

Update the forwarder address.


```solidity
function setForwarder(address _forwarder) external onlyOwner;
```

### registerNoteParams


```solidity
function registerNoteParams(bytes32 noteId, PricingParams calldata params) external override;
```

### getAcceptedPricing


```solidity
function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory);
```

### isPricingFulfilled

Check if pricing has been fulfilled for a note.


```solidity
function isPricingFulfilled(bytes32 noteId) external view returns (bool);
```

### _processPricing


```solidity
function _processPricing(bytes32 noteId, PricingResult memory result) internal;
```

## Events
### PricingRequested

```solidity
event PricingRequested(bytes32 indexed noteId);
```

### PricingAccepted

```solidity
event PricingAccepted(bytes32 indexed noteId, uint16 putPremiumBps, uint16 kiProbabilityBps);
```

### ForwarderUpdated

```solidity
event ForwarderUpdated(address indexed newForwarder);
```

## Errors
### OnlyForwarder

```solidity
error OnlyForwarder();
```

### PremiumOutOfBounds

```solidity
error PremiumOutOfBounds(uint16 premium);
```

### KIProbabilityTooHigh

```solidity
error KIProbabilityTooHigh(uint16 kiProb);
```

### PricingAlreadyFulfilled

```solidity
error PricingAlreadyFulfilled(bytes32 noteId);
```

### PricingCrossCheckFailed

```solidity
error PricingCrossCheckFailed(bytes32 noteId);
```

### NoteNotRegistered

```solidity
error NoteNotRegistered(bytes32 noteId);
```

