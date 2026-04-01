// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { CouponStreamer } from "../../src/integrations/SablierStream.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract CouponStreamerTest is Test {
    CouponStreamer public streamer;
    MockUSDC public usdc;

    address owner = address(this);
    address holder = address(0xBEEF);
    address stranger = address(0xDEAD);

    bytes32 noteId = keccak256("NOTE_1");

    uint256 constant DEPOSIT = 1_000e6; // 1000 USDC
    uint256 constant DURATION = 30 days;

    function setUp() public {
        usdc = new MockUSDC();
        streamer = new CouponStreamer(address(usdc), owner);

        // Fund owner and approve streamer
        usdc.mint(owner, 100_000e6);
        usdc.approve(address(streamer), type(uint256).max);
    }

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------

    function _createStream() internal returns (uint256 streamId) {
        streamId = streamer.startCouponStream(
            noteId, holder, DEPOSIT, block.timestamp, block.timestamp + DURATION
        );
    }

    // ----------------------------------------------------------------
    // startCouponStream
    // ----------------------------------------------------------------

    function test_startCouponStream() public {
        uint256 balBefore = usdc.balanceOf(owner);
        uint256 streamId = _createStream();

        assertEq(streamId, 1);
        assertEq(streamer.nextStreamId(), 2);
        assertEq(usdc.balanceOf(address(streamer)), DEPOSIT);
        assertEq(usdc.balanceOf(owner), balBefore - DEPOSIT);
        assertEq(streamer.streamToNote(streamId), noteId);

        uint256[] memory ids = streamer.getNoteStreams(noteId);
        assertEq(ids.length, 1);
        assertEq(ids[0], streamId);
    }

    function test_startCouponStream_reverts_invalidTimeRange() public {
        vm.expectRevert(CouponStreamer.InvalidTimeRange.selector);
        streamer.startCouponStream(noteId, holder, DEPOSIT, 100, 100);
    }

    function test_startCouponStream_reverts_zeroAmount() public {
        vm.expectRevert(CouponStreamer.ZeroAmount.selector);
        streamer.startCouponStream(noteId, holder, 0, block.timestamp, block.timestamp + DURATION);
    }

    function test_startCouponStream_reverts_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        streamer.startCouponStream(noteId, holder, DEPOSIT, block.timestamp, block.timestamp + DURATION);
    }

    function test_startCouponStream_reverts_tooManyStreams() public {
        for (uint256 i = 0; i < streamer.MAX_STREAMS_PER_NOTE(); i++) {
            streamer.startCouponStream(
                noteId, holder, 10e6, block.timestamp, block.timestamp + DURATION
            );
        }
        vm.expectRevert(abi.encodeWithSelector(CouponStreamer.TooManyStreams.selector, noteId));
        streamer.startCouponStream(noteId, holder, 10e6, block.timestamp, block.timestamp + DURATION);
    }

    // ----------------------------------------------------------------
    // Linear vesting math
    // ----------------------------------------------------------------

    function test_vesting_0pct_before_start() public {
        uint256 start = block.timestamp + 1 hours;
        uint256 streamId = streamer.startCouponStream(
            noteId, holder, DEPOSIT, start, start + DURATION
        );

        assertEq(streamer.getStreamedAmount(streamId), 0);
        assertEq(streamer.getWithdrawable(streamId), 0);
    }

    function test_vesting_25pct() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + DURATION / 4);

        uint256 expected = DEPOSIT / 4;
        assertEq(streamer.getStreamedAmount(streamId), expected);
        assertEq(streamer.getWithdrawable(streamId), expected);
    }

    function test_vesting_50pct() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + DURATION / 2);

        uint256 expected = DEPOSIT / 2;
        assertEq(streamer.getStreamedAmount(streamId), expected);
    }

    function test_vesting_75pct() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + (DURATION * 3) / 4);

        uint256 expected = (DEPOSIT * 3) / 4;
        assertEq(streamer.getStreamedAmount(streamId), expected);
    }

    function test_vesting_100pct() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + DURATION);

        assertEq(streamer.getStreamedAmount(streamId), DEPOSIT);
        assertEq(streamer.getWithdrawable(streamId), DEPOSIT);
    }

    function test_vesting_past_end() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + DURATION + 100 days);

        // Should clamp at deposit, not overflow
        assertEq(streamer.getStreamedAmount(streamId), DEPOSIT);
    }

    // ----------------------------------------------------------------
    // withdraw
    // ----------------------------------------------------------------

    function test_withdraw_partial() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + DURATION / 2);

        uint256 expected = DEPOSIT / 2;
        vm.prank(holder);
        streamer.withdraw(streamId);

        assertEq(usdc.balanceOf(holder), expected);

        // Withdraw the rest at end
        vm.warp(block.timestamp + DURATION / 2);
        uint256 remaining = DEPOSIT - expected;

        vm.prank(holder);
        streamer.withdraw(streamId);

        assertEq(usdc.balanceOf(holder), DEPOSIT);
        assertEq(streamer.getWithdrawable(streamId), 0);

        // Check stream state
        (, uint128 deposit,,,uint128 withdrawn,) = streamer.getStream(streamId);
        assertEq(deposit, DEPOSIT);
        assertEq(withdrawn, DEPOSIT);
    }

    function test_withdraw_full_at_end() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + DURATION);

        vm.prank(holder);
        streamer.withdraw(streamId);

        assertEq(usdc.balanceOf(holder), DEPOSIT);
    }

    function test_withdraw_reverts_notRecipient() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + DURATION / 2);

        vm.prank(stranger);
        vm.expectRevert(CouponStreamer.NotRecipient.selector);
        streamer.withdraw(streamId);
    }

    function test_withdraw_reverts_nothingToWithdraw() public {
        uint256 streamId = _createStream();
        // Don't warp — nothing vested yet

        vm.prank(holder);
        vm.expectRevert(CouponStreamer.NothingToWithdraw.selector);
        streamer.withdraw(streamId);
    }

    function test_withdraw_reverts_doubleWithdraw() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + DURATION / 2);

        vm.prank(holder);
        streamer.withdraw(streamId);

        // Second withdraw at same timestamp — nothing new vested
        vm.prank(holder);
        vm.expectRevert(CouponStreamer.NothingToWithdraw.selector);
        streamer.withdraw(streamId);
    }

    // ----------------------------------------------------------------
    // cancelStream
    // ----------------------------------------------------------------

    function test_cancelStream_midway() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + DURATION / 2);

        uint256 ownerBefore = usdc.balanceOf(owner);
        streamer.cancelStream(streamId);

        // Owner gets ~50% refund
        uint256 vested = DEPOSIT / 2;
        uint256 refunded = DEPOSIT - vested;
        assertEq(usdc.balanceOf(owner), ownerBefore + refunded);

        // Holder can still withdraw vested portion
        vm.prank(holder);
        streamer.withdraw(streamId);
        assertEq(usdc.balanceOf(holder), vested);
    }

    function test_cancelStream_after_partial_withdraw() public {
        uint256 streamId = _createStream();

        // Holder withdraws at 25%
        vm.warp(block.timestamp + DURATION / 4);
        vm.prank(holder);
        streamer.withdraw(streamId);
        uint256 withdrawn25 = usdc.balanceOf(holder);
        assertEq(withdrawn25, DEPOSIT / 4);

        // Owner cancels at 50%
        vm.warp(block.timestamp + DURATION / 4);
        uint256 ownerBefore = usdc.balanceOf(owner);
        streamer.cancelStream(streamId);

        // Refund = deposit - vested_at_50% = 50%
        uint256 vestedAt50 = DEPOSIT / 2;
        uint256 refunded = DEPOSIT - vestedAt50;
        assertEq(usdc.balanceOf(owner), ownerBefore + refunded);

        // Holder can withdraw remaining vested (50% - 25% = 25%)
        vm.prank(holder);
        streamer.withdraw(streamId);
        assertEq(usdc.balanceOf(holder), vestedAt50);
    }

    function test_cancelStream_at_start() public {
        uint256 streamId = _createStream();
        // Cancel immediately at startTime — 0 vested, full refund

        uint256 ownerBefore = usdc.balanceOf(owner);
        streamer.cancelStream(streamId);

        assertEq(usdc.balanceOf(owner), ownerBefore + DEPOSIT);

        // Holder gets nothing
        vm.prank(holder);
        vm.expectRevert(CouponStreamer.NothingToWithdraw.selector);
        streamer.withdraw(streamId);
    }

    function test_cancelStream_at_end() public {
        uint256 streamId = _createStream();
        vm.warp(block.timestamp + DURATION);

        // Cancel after full vest — 0 refund
        uint256 ownerBefore = usdc.balanceOf(owner);
        streamer.cancelStream(streamId);
        assertEq(usdc.balanceOf(owner), ownerBefore); // no refund

        // Holder can still withdraw full amount
        vm.prank(holder);
        streamer.withdraw(streamId);
        assertEq(usdc.balanceOf(holder), DEPOSIT);
    }

    function test_cancelStream_reverts_alreadyCanceled() public {
        uint256 streamId = _createStream();
        streamer.cancelStream(streamId);

        vm.expectRevert(abi.encodeWithSelector(CouponStreamer.StreamAlreadyCanceled.selector, streamId));
        streamer.cancelStream(streamId);
    }

    function test_cancelStream_reverts_onlyOwner() public {
        uint256 streamId = _createStream();

        vm.prank(stranger);
        vm.expectRevert();
        streamer.cancelStream(streamId);
    }

    function test_cancelStream_reverts_notFound() public {
        vm.expectRevert(abi.encodeWithSelector(CouponStreamer.StreamNotFound.selector, 999));
        streamer.cancelStream(999);
    }

    // ----------------------------------------------------------------
    // cancelAllNoteStreams
    // ----------------------------------------------------------------

    function test_cancelAllNoteStreams() public {
        // Create 3 streams for same note
        uint256 s1 = _createStream();
        uint256 s2 = _createStream();
        uint256 s3 = _createStream();

        vm.warp(block.timestamp + DURATION / 2);

        uint256 ownerBefore = usdc.balanceOf(owner);
        uint256 totalRefunded = streamer.cancelAllNoteStreams(noteId);

        // Each stream: 50% vested → 50% refunded
        uint256 expectedRefundPerStream = DEPOSIT / 2;
        assertEq(totalRefunded, expectedRefundPerStream * 3);
        assertEq(usdc.balanceOf(owner), ownerBefore + totalRefunded);

        // All streams marked canceled
        (,,,,, bool c1) = streamer.getStream(s1);
        (,,,,, bool c2) = streamer.getStream(s2);
        (,,,,, bool c3) = streamer.getStream(s3);
        assertTrue(c1);
        assertTrue(c2);
        assertTrue(c3);
    }

    function test_cancelAllNoteStreams_skips_already_canceled() public {
        uint256 s1 = _createStream();
        uint256 s2 = _createStream();

        // Cancel s1 individually first
        streamer.cancelStream(s1);

        vm.warp(block.timestamp + DURATION / 2);

        uint256 ownerBefore = usdc.balanceOf(owner);
        uint256 totalRefunded = streamer.cancelAllNoteStreams(noteId);

        // Only s2 refunds (50%)
        assertEq(totalRefunded, DEPOSIT / 2);
    }

    function test_cancelAllNoteStreams_empty_noteId() public {
        bytes32 emptyNote = keccak256("NONEXISTENT");
        uint256 totalRefunded = streamer.cancelAllNoteStreams(emptyNote);
        assertEq(totalRefunded, 0);
    }

    // ----------------------------------------------------------------
    // getStream / view helpers
    // ----------------------------------------------------------------

    function test_getStream() public {
        uint256 start = block.timestamp;
        uint256 streamId = _createStream();

        (address recipient, uint128 deposit, uint40 startTime, uint40 endTime, uint128 withdrawn, bool canceled) =
            streamer.getStream(streamId);

        assertEq(recipient, holder);
        assertEq(deposit, DEPOSIT);
        assertEq(startTime, start);
        assertEq(endTime, start + DURATION);
        assertEq(withdrawn, 0);
        assertFalse(canceled);
    }

    // ----------------------------------------------------------------
    // recoverToken
    // ----------------------------------------------------------------

    function test_recoverToken() public {
        MockUSDC other = new MockUSDC();
        other.mint(address(streamer), 500e6);

        streamer.recoverToken(address(other), 500e6);
        assertEq(other.balanceOf(owner), 500e6);
    }

    function test_recoverToken_reverts_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        streamer.recoverToken(address(usdc), 1);
    }
}
