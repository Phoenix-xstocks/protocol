// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { XYieldVault } from "../../src/core/XYieldVault.sol";
import { NoteToken } from "../../src/core/NoteToken.sol";
import { IAutocallEngine } from "../../src/interfaces/IAutocallEngine.sol";
import { State } from "../../src/interfaces/IAutocallEngine.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ================================================================
// Mock contracts
// ================================================================

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockAutocallEngine is IAutocallEngine {
    mapping(bytes32 => State) public states;
    uint256 public count;

    function createNote(address[] calldata, uint256, address) external returns (bytes32) {
        bytes32 id = keccak256(abi.encodePacked(count++));
        states[id] = State.Created;
        return id;
    }

    function observe(bytes32) external {}
    function settleKI(bytes32, bool) external {}

    function getState(bytes32 noteId) external view returns (State) {
        return states[noteId];
    }

    function getNoteCount() external view returns (uint256) {
        return count;
    }
}

// ================================================================
// Test contract
// ================================================================

contract XYieldVaultTest is Test {
    XYieldVault public vault;
    MockUSDC public usdc;
    MockAutocallEngine public engine;
    NoteToken public noteToken;

    address admin = address(this);
    address operator = address(0xBEEF);
    address depositor = address(0x1234);
    address receiver = address(0x5678);

    bytes32 constant MOCK_NOTE_ID = bytes32(uint256(1));

    function setUp() public {
        usdc = new MockUSDC();
        engine = new MockAutocallEngine();
        noteToken = new NoteToken(admin);

        vault = new XYieldVault(admin, address(usdc), address(engine), address(noteToken));

        vault.grantRole(vault.OPERATOR_ROLE(), operator);

        // Grant vault the minter role on NoteToken
        noteToken.grantRole(noteToken.MINTER_ROLE(), address(vault));

        // Fund depositor
        usdc.mint(depositor, 1_000_000e6);
        vm.prank(depositor);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ================================================================
    // Helpers
    // ================================================================

    function _requestDeposit(uint256 amount) internal returns (uint256 requestId) {
        vm.prank(depositor);
        requestId = vault.requestDeposit(amount, receiver);
    }

    function _requestAndFulfill(uint256 amount) internal returns (uint256 requestId) {
        requestId = _requestDeposit(amount);

        address[] memory basket = new address[](3);
        basket[0] = address(0xA);
        basket[1] = address(0xB);
        basket[2] = address(0xC);

        vm.prank(operator);
        vault.fulfillDeposit(requestId, MOCK_NOTE_ID, basket);
    }

    // ================================================================
    // requestDeposit tests
    // ================================================================

    function test_requestDeposit_success() public {
        uint256 requestId = _requestDeposit(1000e6);

        assertEq(requestId, 0);
        // USDC transferred to vault
        assertEq(usdc.balanceOf(address(vault)), 1000e6);
    }

    function test_requestDeposit_below_minimum_reverts() public {
        vm.prank(depositor);
        vm.expectRevert(XYieldVault.BelowMinDeposit.selector);
        vault.requestDeposit(50e6, receiver); // $50 < $100 min
    }

    function test_requestDeposit_above_maximum_reverts() public {
        usdc.mint(depositor, 200_000e6);

        vm.prank(depositor);
        vm.expectRevert(XYieldVault.AboveMaxDeposit.selector);
        vault.requestDeposit(150_000e6, receiver); // $150k > $100k max
    }

    function test_requestDeposit_zero_reverts() public {
        vm.prank(depositor);
        vm.expectRevert(XYieldVault.ZeroAmount.selector);
        vault.requestDeposit(0, receiver);
    }

    function test_requestDeposit_increments_id() public {
        uint256 id1 = _requestDeposit(1000e6);
        uint256 id2 = _requestDeposit(2000e6);

        assertEq(id1, 0);
        assertEq(id2, 1);
    }

    // ================================================================
    // fulfillDeposit tests
    // ================================================================

    function test_fulfillDeposit_success() public {
        uint256 requestId = _requestDeposit(1000e6);

        address[] memory basket = new address[](3);
        basket[0] = address(0xA);
        basket[1] = address(0xB);
        basket[2] = address(0xC);

        vm.prank(operator);
        vault.fulfillDeposit(requestId, MOCK_NOTE_ID, basket);

        (, , , , , , XYieldVault.RequestStatus status) = vault.requests(requestId);
        assertEq(uint256(status), uint256(XYieldVault.RequestStatus.ReadyToClaim));
    }

    function test_fulfillDeposit_only_operator() public {
        uint256 requestId = _requestDeposit(1000e6);
        address[] memory basket = new address[](3);

        vm.prank(depositor);
        vm.expectRevert();
        vault.fulfillDeposit(requestId, MOCK_NOTE_ID, basket);
    }

    function test_fulfillDeposit_not_pending_reverts() public {
        uint256 requestId = _requestAndFulfill(1000e6);

        address[] memory basket = new address[](3);

        vm.prank(operator);
        vm.expectRevert(XYieldVault.InvalidRequestStatus.selector);
        vault.fulfillDeposit(requestId, MOCK_NOTE_ID, basket);
    }

    // ================================================================
    // claimDeposit tests
    // ================================================================

    function test_claimDeposit_success() public {
        uint256 requestId = _requestAndFulfill(1000e6);

        vm.prank(receiver);
        uint256 tokenId = vault.claimDeposit(requestId);

        assertEq(tokenId, uint256(MOCK_NOTE_ID));
        assertEq(noteToken.balanceOf(receiver, tokenId), 1000e6);
        assertEq(vault.totalAssets(), 1000e6);
        assertEq(vault.activeNoteCount(), 1);
    }

    function test_claimDeposit_not_receiver_reverts() public {
        uint256 requestId = _requestAndFulfill(1000e6);

        vm.prank(depositor); // not receiver
        vm.expectRevert(XYieldVault.NotReceiver.selector);
        vault.claimDeposit(requestId);
    }

    function test_claimDeposit_after_deadline_reverts() public {
        uint256 requestId = _requestAndFulfill(1000e6);

        // Warp past 24h
        vm.warp(block.timestamp + 25 hours);

        vm.prank(receiver);
        vm.expectRevert(XYieldVault.ClaimDeadlinePassed.selector);
        vault.claimDeposit(requestId);
    }

    function test_claimDeposit_within_deadline() public {
        uint256 requestId = _requestAndFulfill(1000e6);

        // Just before deadline
        vm.warp(block.timestamp + 23 hours);

        vm.prank(receiver);
        vault.claimDeposit(requestId);

        assertEq(vault.activeNoteCount(), 1);
    }

    function test_claimDeposit_double_claim_reverts() public {
        uint256 requestId = _requestAndFulfill(1000e6);

        vm.prank(receiver);
        vault.claimDeposit(requestId);

        vm.prank(receiver);
        vm.expectRevert(XYieldVault.InvalidRequestStatus.selector);
        vault.claimDeposit(requestId);
    }

    // ================================================================
    // refundDeposit tests
    // ================================================================

    function test_refund_pending_after_24h() public {
        uint256 requestId = _requestDeposit(1000e6);
        uint256 depositorBal = usdc.balanceOf(depositor);

        vm.warp(block.timestamp + 25 hours);
        vault.refundDeposit(requestId);

        assertEq(usdc.balanceOf(depositor), depositorBal + 1000e6);
    }

    function test_refund_pending_before_24h_reverts() public {
        uint256 requestId = _requestDeposit(1000e6);

        vm.warp(block.timestamp + 12 hours);
        vm.expectRevert(XYieldVault.ClaimDeadlineNotReached.selector);
        vault.refundDeposit(requestId);
    }

    function test_refund_ready_after_24h() public {
        uint256 requestId = _requestAndFulfill(1000e6);
        uint256 depositorBal = usdc.balanceOf(depositor);

        vm.warp(block.timestamp + 25 hours);
        vault.refundDeposit(requestId);

        assertEq(usdc.balanceOf(depositor), depositorBal + 1000e6);
    }

    function test_refund_claimed_reverts() public {
        uint256 requestId = _requestAndFulfill(1000e6);

        vm.prank(receiver);
        vault.claimDeposit(requestId);

        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert(XYieldVault.InvalidRequestStatus.selector);
        vault.refundDeposit(requestId);
    }

    // ================================================================
    // Position limits tests
    // ================================================================

    function test_tvl_limit() public {
        // Deposit close to MAX_TVL
        usdc.mint(depositor, 10_000_000e6);
        vm.prank(depositor);
        usdc.approve(address(vault), type(uint256).max);

        // Fill up TVL by claiming deposits
        for (uint256 i = 0; i < 50; i++) {
            uint256 rid = _requestDeposit(100_000e6);
            bytes32 nid = bytes32(uint256(i + 100));
            address[] memory b = new address[](3);
            b[0] = address(0xA);
            b[1] = address(0xB);
            b[2] = address(0xC);
            vm.prank(operator);
            vault.fulfillDeposit(rid, nid, b);
            vm.prank(receiver);
            vault.claimDeposit(rid);
        }
        // 50 * 100k = 5M = MAX_TVL

        // Next deposit should fail
        vm.prank(depositor);
        vm.expectRevert(XYieldVault.TVLExceeded.selector);
        vault.requestDeposit(1000e6, receiver);
    }

    // ================================================================
    // Accounting tests
    // ================================================================

    function test_noteSettled_decrements_accounting() public {
        uint256 requestId = _requestAndFulfill(1000e6);
        vm.prank(receiver);
        vault.claimDeposit(requestId);

        assertEq(vault.totalAssets(), 1000e6);
        assertEq(vault.activeNoteCount(), 1);

        vm.prank(operator);
        vault.noteSettled(1000e6);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.activeNoteCount(), 0);
    }

    function test_noteSettled_only_operator() public {
        vm.prank(depositor);
        vm.expectRevert();
        vault.noteSettled(1000e6);
    }

    // ================================================================
    // maxDeposit tests
    // ================================================================

    function test_maxDeposit_initial() public view {
        uint256 max = vault.maxDeposit(depositor);
        assertEq(max, 100_000e6); // MAX_NOTE_SIZE since TVL is 0
    }

    // ================================================================
    // Redeem stubs test
    // ================================================================

    function test_requestRedeem_reverts() public {
        vm.expectRevert();
        vault.requestRedeem(0);
    }

    function test_claimRedeem_reverts() public {
        vm.expectRevert();
        vault.claimRedeem(0);
    }
}
