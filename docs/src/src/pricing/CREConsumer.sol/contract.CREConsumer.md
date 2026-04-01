# CREConsumer
[Git Source](https://github.com/Phoenix-xstocks/protocol/blob/ea8699889f4c6ecd6e3b33d2e2376beb31f700bf/src/pricing/CREConsumer.sol)

**Inherits:**
[ICREConsumer](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/interfaces/ICREConsumer.sol/interface.ICREConsumer.md), [IReceiver](/Users/thomashussenet/Documents/hackathon/xstocks/protocol/docs/src/src/pricing/CREConsumer.sol/interface.IReceiver.md), ERC165, Ownable

Receives pricing results from Chainlink CRE workflow via the KeystoneForwarder.
Implements IReceiver + ERC165 for CRE compatibility. Performs bounds check and
cross-check against OptionPricer before accepting.


## State Variables
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


### forwarder
Address of the Chainlink KeystoneForwarder (validates DON signatures).


```solidity
address public forwarder;
```


### optionPricer

```solidity
IOptionPricer public optionPricer;
```


### autocallEngine
AutocallEngine address — allowed to register note params on createNote().


```solidity
address public autocallEngine;
```


### expectedWorkflowOwner
Optional: restrict to a specific CRE workflow owner address.


```solidity
address public expectedWorkflowOwner;
```


### acceptedPricings

```solidity
mapping(bytes32 => PricingResult) public acceptedPricings;
```


### isPricingAccepted

```solidity
mapping(bytes32 => bool) public isPricingAccepted;
```


### noteParams

```solidity
mapping(bytes32 => PricingParams) internal noteParams;
```


### hasNoteParams

```solidity
mapping(bytes32 => bool) public hasNoteParams;
```


## Functions
### constructor


```solidity
constructor(address _forwarder, address _optionPricer, address _owner) Ownable(_owner);
```

### onReport

Called by the CRE KeystoneForwarder after DON consensus.
metadata = abi.encodePacked(bytes32 workflowId, bytes10 workflowName, address workflowOwner)
report   = abi.encode(bytes32 noteId, PricingResult result)


```solidity
function onReport(bytes calldata metadata, bytes calldata report) external override;
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public view override returns (bool);
```

### registerNoteParams


```solidity
function registerNoteParams(bytes32 noteId, PricingParams calldata params) external;
```

### setForwarder

Update the forwarder address (e.g. switching from simulation to production).


```solidity
function setForwarder(address _forwarder) external onlyOwner;
```

### setExpectedWorkflowOwner

Restrict reports to a specific CRE workflow owner. Set address(0) to disable.


```solidity
function setExpectedWorkflowOwner(address _owner) external onlyOwner;
```

### setOptionPricer


```solidity
function setOptionPricer(address _optionPricer) external onlyOwner;
```

### setAutocallEngine

Set the AutocallEngine address allowed to register note params.


```solidity
function setAutocallEngine(address _engine) external onlyOwner;
```

### getAcceptedPricing


```solidity
function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory);
```

### getNoteParams


```solidity
function getNoteParams(bytes32 noteId) external view returns (PricingParams memory);
```

### _processPricing


```solidity
function _processPricing(bytes32 noteId, PricingResult memory result) internal;
```

## Events
### PricingAccepted

```solidity
event PricingAccepted(bytes32 indexed noteId, uint16 putPremiumBps, uint16 kiProbabilityBps);
```

### NoteParamsRegistered

```solidity
event NoteParamsRegistered(bytes32 indexed noteId);
```

### ForwarderUpdated

```solidity
event ForwarderUpdated(address indexed newForwarder);
```

### AutocallEngineUpdated

```solidity
event AutocallEngineUpdated(address indexed newEngine);
```

