// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { CREConsumer, IReceiver } from "../../src/pricing/CREConsumer.sol";
import { PricingResult } from "../../src/interfaces/ICREConsumer.sol";
import { IOptionPricer, PricingParams } from "../../src/interfaces/IOptionPricer.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract MockOptionPricer is IOptionPricer {
    bool public approveAll = true;
    uint256 public approxReturn = 800;

    function setApproveAll(bool _approve) external {
        approveAll = _approve;
    }

    function setApproxReturn(uint256 _approx) external {
        approxReturn = _approx;
    }

    function verifyPricing(
        PricingParams calldata,
        uint256,
        bytes32
    ) external view override returns (bool approved, uint256 onChainApprox) {
        return (approveAll, approxReturn);
    }
}

contract CREConsumerTest is Test {
    CREConsumer public consumer;
    MockOptionPricer public pricer;

    address owner = address(this);
    address forwarderAddr = address(0xCCCC);
    address nonOwner = address(0xDEAD);

    bytes32 constant NOTE_1 = bytes32(uint256(1));
    bytes32 constant NOTE_2 = bytes32(uint256(2));
    bytes32 constant NOTE_3 = bytes32(uint256(3));

    function setUp() public {
        pricer = new MockOptionPricer();
        consumer = new CREConsumer(forwarderAddr, address(pricer), owner);
    }

    function _defaultParams() internal pure returns (PricingParams memory) {
        address[] memory basket = new address[](3);
        basket[0] = address(0x1);
        basket[1] = address(0x2);
        basket[2] = address(0x3);
        return PricingParams({
            basket: basket,
            kiBarrierBps: 7000,
            couponBarrierBps: 7000,
            autocallTriggerBps: 10000,
            stepDownBps: 200,
            maturityDays: 180,
            numObservations: 6
        });
    }

    function _defaultPricingResult() internal pure returns (PricingResult memory) {
        return PricingResult({
            putPremiumBps: 800,
            kiProbabilityBps: 500,
            expectedKILossBps: 200,
            vegaBps: 100,
            inputsHash: bytes32(uint256(0xABCD))
        });
    }

    /// @dev Build metadata: abi.encodePacked(bytes32 workflowId, bytes10 workflowName, address workflowOwner)
    function _buildMetadata(address workflowOwner) internal pure returns (bytes memory) {
        bytes32 workflowId = bytes32(uint256(0x1234));
        bytes10 workflowName = bytes10(bytes32(uint256(0x5678)));
        return abi.encodePacked(workflowId, workflowName, workflowOwner);
    }

    /// @dev Build report: abi.encode(bytes32 noteId, PricingResult result)
    function _buildReport(bytes32 noteId, PricingResult memory result) internal pure returns (bytes memory) {
        return abi.encode(noteId, result);
    }

    function _registerAndFulfill(bytes32 noteId) internal {
        consumer.registerNoteParams(noteId, _defaultParams());
        bytes memory metadata = _buildMetadata(address(0));
        bytes memory report = _buildReport(noteId, _defaultPricingResult());
        vm.prank(forwarderAddr);
        consumer.onReport(metadata, report);
    }

    // ---------------------------------------------------------------
    // ERC165 support
    // ---------------------------------------------------------------
    function test_supportsInterface_IReceiver() public view {
        assertTrue(consumer.supportsInterface(type(IReceiver).interfaceId));
    }

    function test_supportsInterface_IERC165() public view {
        assertTrue(consumer.supportsInterface(type(IERC165).interfaceId));
    }

    // ---------------------------------------------------------------
    // registerNoteParams: only owner
    // ---------------------------------------------------------------
    function test_registerNoteParams_success() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());
        assertTrue(consumer.hasNoteParams(NOTE_1));
    }

    function test_registerNoteParams_emitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit CREConsumer.NoteParamsRegistered(NOTE_1);
        consumer.registerNoteParams(NOTE_1, _defaultParams());
    }

    function test_registerNoteParams_revertsForNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        consumer.registerNoteParams(NOTE_1, _defaultParams());
    }

    function test_registerNoteParams_revertsOnDuplicate() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());
        vm.expectRevert("already registered");
        consumer.registerNoteParams(NOTE_1, _defaultParams());
    }

    function test_getNoteParams_returnsCorrectData() public {
        PricingParams memory params = _defaultParams();
        consumer.registerNoteParams(NOTE_1, params);
        PricingParams memory stored = consumer.getNoteParams(NOTE_1);
        assertEq(stored.kiBarrierBps, 7000);
        assertEq(stored.couponBarrierBps, 7000);
        assertEq(stored.maturityDays, 180);
        assertEq(stored.basket.length, 3);
    }

    function test_getNoteParams_revertsWhenNotRegistered() public {
        vm.expectRevert("not registered");
        consumer.getNoteParams(NOTE_1);
    }

    // ---------------------------------------------------------------
    // onReport: success path
    // ---------------------------------------------------------------
    function test_onReport_success() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        bytes memory metadata = _buildMetadata(address(0));
        bytes memory report = _buildReport(NOTE_1, result);

        vm.prank(forwarderAddr);
        vm.expectEmit(true, false, false, true);
        emit CREConsumer.PricingAccepted(NOTE_1, result.putPremiumBps, result.kiProbabilityBps);
        consumer.onReport(metadata, report);

        assertTrue(consumer.isPricingAccepted(NOTE_1));
    }

    // ---------------------------------------------------------------
    // onReport: only forwarder
    // ---------------------------------------------------------------
    function test_onReport_revertsForNonForwarder() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());
        bytes memory metadata = _buildMetadata(address(0));
        bytes memory report = _buildReport(NOTE_1, _defaultPricingResult());

        vm.prank(nonOwner);
        vm.expectRevert("only forwarder");
        consumer.onReport(metadata, report);
    }

    // ---------------------------------------------------------------
    // onReport: note must be registered
    // ---------------------------------------------------------------
    function test_onReport_revertsWhenNoteNotRegistered() public {
        bytes memory metadata = _buildMetadata(address(0));
        bytes memory report = _buildReport(NOTE_1, _defaultPricingResult());

        vm.prank(forwarderAddr);
        vm.expectRevert("note not registered");
        consumer.onReport(metadata, report);
    }

    // ---------------------------------------------------------------
    // onReport: bounds check (MIN/MAX_PREMIUM)
    // ---------------------------------------------------------------
    function test_onReport_revertsOnPremiumTooLow() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        result.putPremiumBps = 299; // below MIN_PREMIUM (300)

        vm.prank(forwarderAddr);
        vm.expectRevert("premium too low");
        consumer.onReport(_buildMetadata(address(0)), _buildReport(NOTE_1, result));
    }

    function test_onReport_revertsOnPremiumTooHigh() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        result.putPremiumBps = 1501; // above MAX_PREMIUM (1500)

        vm.prank(forwarderAddr);
        vm.expectRevert("premium too high");
        consumer.onReport(_buildMetadata(address(0)), _buildReport(NOTE_1, result));
    }

    function test_onReport_premiumAtMinBoundary() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        result.putPremiumBps = 300; // exactly MIN_PREMIUM

        vm.prank(forwarderAddr);
        consumer.onReport(_buildMetadata(address(0)), _buildReport(NOTE_1, result));
        assertTrue(consumer.isPricingAccepted(NOTE_1));
    }

    function test_onReport_premiumAtMaxBoundary() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        result.putPremiumBps = 1500; // exactly MAX_PREMIUM

        vm.prank(forwarderAddr);
        consumer.onReport(_buildMetadata(address(0)), _buildReport(NOTE_1, result));
        assertTrue(consumer.isPricingAccepted(NOTE_1));
    }

    function test_onReport_revertsOnKIProbTooHigh() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        result.kiProbabilityBps = 1501; // above MAX_KI_PROB (1500)

        vm.prank(forwarderAddr);
        vm.expectRevert("KI prob too high");
        consumer.onReport(_buildMetadata(address(0)), _buildReport(NOTE_1, result));
    }

    // ---------------------------------------------------------------
    // onReport: cross-check with OptionPricer
    // ---------------------------------------------------------------
    function test_onReport_revertsOnOptionPricerRejection() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());
        pricer.setApproveAll(false);

        vm.prank(forwarderAddr);
        vm.expectRevert("CRE vs on-chain divergence");
        consumer.onReport(_buildMetadata(address(0)), _buildReport(NOTE_1, _defaultPricingResult()));
    }

    // ---------------------------------------------------------------
    // getAcceptedPricing: returns correct data
    // ---------------------------------------------------------------
    function test_getAcceptedPricing_returnsCorrectData() public {
        _registerAndFulfill(NOTE_1);

        PricingResult memory result = consumer.getAcceptedPricing(NOTE_1);
        assertEq(result.putPremiumBps, 800);
        assertEq(result.kiProbabilityBps, 500);
        assertEq(result.expectedKILossBps, 200);
        assertEq(result.vegaBps, 100);
        assertEq(result.inputsHash, bytes32(uint256(0xABCD)));
    }

    // ---------------------------------------------------------------
    // getAcceptedPricing: reverts if not accepted
    // ---------------------------------------------------------------
    function test_getAcceptedPricing_revertsWhenNotAccepted() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());
        // registered but not fulfilled
        vm.expectRevert("pricing not accepted");
        consumer.getAcceptedPricing(NOTE_1);
    }

    function test_getAcceptedPricing_revertsForUnknownNote() public {
        vm.expectRevert("pricing not accepted");
        consumer.getAcceptedPricing(NOTE_1);
    }

    // ---------------------------------------------------------------
    // Duplicate pricing rejection
    // ---------------------------------------------------------------
    function test_onReport_revertsDuplicateAcceptance() public {
        _registerAndFulfill(NOTE_1);

        // Try to fulfill again
        vm.prank(forwarderAddr);
        vm.expectRevert("already accepted");
        consumer.onReport(_buildMetadata(address(0)), _buildReport(NOTE_1, _defaultPricingResult()));
    }

    // ---------------------------------------------------------------
    // Multiple notes
    // ---------------------------------------------------------------
    function test_multipleNotes() public {
        _registerAndFulfill(NOTE_1);
        _registerAndFulfill(NOTE_2);

        PricingResult memory r1 = consumer.getAcceptedPricing(NOTE_1);
        PricingResult memory r2 = consumer.getAcceptedPricing(NOTE_2);

        assertEq(r1.putPremiumBps, 800);
        assertEq(r2.putPremiumBps, 800);
    }

    // ---------------------------------------------------------------
    // setOptionPricer
    // ---------------------------------------------------------------
    function test_setOptionPricer() public {
        MockOptionPricer newPricer = new MockOptionPricer();
        consumer.setOptionPricer(address(newPricer));
        assertEq(address(consumer.optionPricer()), address(newPricer));
    }

    function test_setOptionPricer_revertsOnZero() public {
        vm.expectRevert("zero address");
        consumer.setOptionPricer(address(0));
    }

    function test_setOptionPricer_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        consumer.setOptionPricer(address(0x123));
    }

    // ---------------------------------------------------------------
    // setForwarder
    // ---------------------------------------------------------------
    function test_setForwarder() public {
        address newForwarder = address(0xBEEF);
        consumer.setForwarder(newForwarder);
        assertEq(consumer.forwarder(), newForwarder);
    }

    function test_setForwarder_revertsOnZero() public {
        vm.expectRevert("zero forwarder");
        consumer.setForwarder(address(0));
    }

    function test_setForwarder_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        consumer.setForwarder(address(0xBEEF));
    }

    function test_setForwarder_emitsEvent() public {
        address newForwarder = address(0xBEEF);
        vm.expectEmit(true, false, false, false);
        emit CREConsumer.ForwarderUpdated(newForwarder);
        consumer.setForwarder(newForwarder);
    }

    // ---------------------------------------------------------------
    // Workflow owner validation
    // ---------------------------------------------------------------
    function test_onReport_validatesWorkflowOwner() public {
        address expectedOwner = address(0x9999);
        consumer.setExpectedWorkflowOwner(expectedOwner);
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        // Wrong workflow owner
        vm.prank(forwarderAddr);
        vm.expectRevert("unexpected workflow owner");
        consumer.onReport(_buildMetadata(address(0x1111)), _buildReport(NOTE_1, _defaultPricingResult()));

        // Correct workflow owner
        vm.prank(forwarderAddr);
        consumer.onReport(_buildMetadata(expectedOwner), _buildReport(NOTE_1, _defaultPricingResult()));
        assertTrue(consumer.isPricingAccepted(NOTE_1));
    }

    function test_onReport_skipsOwnerValidationWhenNotSet() public {
        // expectedWorkflowOwner is address(0) by default — no validation
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        vm.prank(forwarderAddr);
        consumer.onReport(_buildMetadata(address(0x9999)), _buildReport(NOTE_1, _defaultPricingResult()));
        assertTrue(consumer.isPricingAccepted(NOTE_1));
    }

    // ---------------------------------------------------------------
    // Constructor validations
    // ---------------------------------------------------------------
    function test_constructor_revertsZeroForwarder() public {
        vm.expectRevert("zero forwarder");
        new CREConsumer(address(0), address(pricer), owner);
    }

    function test_constructor_revertsZeroPricer() public {
        vm.expectRevert("zero pricer");
        new CREConsumer(forwarderAddr, address(0), owner);
    }

    function test_forwarder_isSetCorrectly() public view {
        assertEq(consumer.forwarder(), forwarderAddr);
    }
}
