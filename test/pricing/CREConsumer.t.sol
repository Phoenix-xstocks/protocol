// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { CREConsumer } from "../../src/pricing/CREConsumer.sol";
import { PricingResult } from "../../src/interfaces/ICREConsumer.sol";
import { IOptionPricer, PricingParams } from "../../src/interfaces/IOptionPricer.sol";

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
    address creRouter = address(0xCCCC);
    address nonOwner = address(0xDEAD);

    bytes32 constant NOTE_1 = bytes32(uint256(1));
    bytes32 constant NOTE_2 = bytes32(uint256(2));
    bytes32 constant NOTE_3 = bytes32(uint256(3));

    function setUp() public {
        pricer = new MockOptionPricer();
        consumer = new CREConsumer(creRouter, address(pricer), owner);
    }

    function _defaultParams() internal pure returns (PricingParams memory) {
        address[] memory basket = new address[](3);
        basket[0] = address(0x1);
        basket[1] = address(0x2);
        basket[2] = address(0x3);
        return PricingParams({
            basket: basket,
            kiBarrierBps: 5000,
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

    function _registerAndFulfill(bytes32 noteId) internal {
        consumer.registerNoteParams(noteId, _defaultParams());
        vm.prank(creRouter);
        consumer.fulfillPricing(noteId, _defaultPricingResult());
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
        assertEq(stored.kiBarrierBps, 5000);
        assertEq(stored.couponBarrierBps, 7000);
        assertEq(stored.maturityDays, 180);
        assertEq(stored.basket.length, 3);
    }

    function test_getNoteParams_revertsWhenNotRegistered() public {
        vm.expectRevert("not registered");
        consumer.getNoteParams(NOTE_1);
    }

    // ---------------------------------------------------------------
    // fulfillPricing: success path
    // ---------------------------------------------------------------
    function test_fulfillPricing_success() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();

        vm.prank(creRouter);
        vm.expectEmit(true, false, false, true);
        emit CREConsumer.PricingAccepted(NOTE_1, result.putPremiumBps, result.kiProbabilityBps);
        consumer.fulfillPricing(NOTE_1, result);

        assertTrue(consumer.isPricingAccepted(NOTE_1));
    }

    // ---------------------------------------------------------------
    // fulfillPricing: only CRE router
    // ---------------------------------------------------------------
    function test_fulfillPricing_revertsForNonRouter() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        vm.prank(nonOwner);
        vm.expectRevert("only CRE router");
        consumer.fulfillPricing(NOTE_1, _defaultPricingResult());
    }

    // ---------------------------------------------------------------
    // fulfillPricing: note must be registered
    // ---------------------------------------------------------------
    function test_fulfillPricing_revertsWhenNoteNotRegistered() public {
        vm.prank(creRouter);
        vm.expectRevert("note not registered");
        consumer.fulfillPricing(NOTE_1, _defaultPricingResult());
    }

    // ---------------------------------------------------------------
    // fulfillPricing: bounds check (MIN/MAX_PREMIUM)
    // ---------------------------------------------------------------
    function test_fulfillPricing_revertsOnPremiumTooLow() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        result.putPremiumBps = 299; // below MIN_PREMIUM (300)

        vm.prank(creRouter);
        vm.expectRevert("premium too low");
        consumer.fulfillPricing(NOTE_1, result);
    }

    function test_fulfillPricing_revertsOnPremiumTooHigh() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        result.putPremiumBps = 1501; // above MAX_PREMIUM (1500)

        vm.prank(creRouter);
        vm.expectRevert("premium too high");
        consumer.fulfillPricing(NOTE_1, result);
    }

    function test_fulfillPricing_premiumAtMinBoundary() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        result.putPremiumBps = 300; // exactly MIN_PREMIUM

        vm.prank(creRouter);
        consumer.fulfillPricing(NOTE_1, result);
        assertTrue(consumer.isPricingAccepted(NOTE_1));
    }

    function test_fulfillPricing_premiumAtMaxBoundary() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        result.putPremiumBps = 1500; // exactly MAX_PREMIUM

        vm.prank(creRouter);
        consumer.fulfillPricing(NOTE_1, result);
        assertTrue(consumer.isPricingAccepted(NOTE_1));
    }

    function test_fulfillPricing_revertsOnKIProbTooHigh() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());

        PricingResult memory result = _defaultPricingResult();
        result.kiProbabilityBps = 1501; // above MAX_KI_PROB (1500)

        vm.prank(creRouter);
        vm.expectRevert("KI prob too high");
        consumer.fulfillPricing(NOTE_1, result);
    }

    // ---------------------------------------------------------------
    // fulfillPricing: cross-check with OptionPricer
    // ---------------------------------------------------------------
    function test_fulfillPricing_revertsOnOptionPricerRejection() public {
        consumer.registerNoteParams(NOTE_1, _defaultParams());
        pricer.setApproveAll(false);

        vm.prank(creRouter);
        vm.expectRevert("CRE vs on-chain divergence");
        consumer.fulfillPricing(NOTE_1, _defaultPricingResult());
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
    function test_fulfillPricing_revertsDuplicateAcceptance() public {
        _registerAndFulfill(NOTE_1);

        // Try to fulfill again
        vm.prank(creRouter);
        vm.expectRevert("already accepted");
        consumer.fulfillPricing(NOTE_1, _defaultPricingResult());
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
    // Constructor validations
    // ---------------------------------------------------------------
    function test_constructor_revertsZeroRouter() public {
        vm.expectRevert("zero router");
        new CREConsumer(address(0), address(pricer), owner);
    }

    function test_constructor_revertsZeroPricer() public {
        vm.expectRevert("zero pricer");
        new CREConsumer(creRouter, address(0), owner);
    }

    function test_creRouter_isImmutable() public view {
        assertEq(consumer.creRouter(), creRouter);
    }
}
