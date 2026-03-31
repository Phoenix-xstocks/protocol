// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { EpochManager } from "../../src/periphery/EpochManager.sol";
import { ReserveFund } from "../../src/periphery/ReserveFund.sol";
import { FeeCollector } from "../../src/periphery/FeeCollector.sol";
import { ICarryEngine } from "../../src/interfaces/ICarryEngine.sol";
import { IHedgeManager } from "../../src/interfaces/IHedgeManager.sol";

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
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockCarryEngine is ICarryEngine {
    uint256 public fundingRate = 550;
    uint256 public lendingRate = 350;

    function collectCarry(bytes32) external pure override returns (uint256, uint256) {
        return (1000e6, 500e6);
    }

    function getTotalCarryRate() external view override returns (uint256) {
        return fundingRate + lendingRate;
    }

    function getFundingRate() external view override returns (uint256) {
        return fundingRate;
    }

    function getLendingRate() external view override returns (uint256) {
        return lendingRate;
    }
}

contract MockHedgeManager is IHedgeManager {
    mapping(bytes32 => int256) public drifts;
    bool public rebalanceCalled;

    function openHedge(bytes32, address[] calldata, uint256) external override {}

    function closeHedge(bytes32) external pure override returns (uint256) {
        return 0;
    }

    function rebalance(bytes32) external override {
        rebalanceCalled = true;
    }

    function getDeltaDrift(bytes32 noteId) external view override returns (int256) {
        return drifts[noteId];
    }

    function setDrift(bytes32 noteId, int256 drift) external {
        drifts[noteId] = drift;
    }
}

contract EpochManagerTest is Test {
    EpochManager public epoch;
    ReserveFund public reserve;
    FeeCollector public feeCollector;
    MockCarryEngine public carry;
    MockHedgeManager public hedge;
    MockUSDC public usdc;

    address public owner;
    address public treasury;
    address public couponRecipient;

    uint256 constant TOTAL_NOTIONAL = 1_000_000e6;
    bytes32 constant NOTE_1 = bytes32(uint256(1));
    bytes32 constant NOTE_2 = bytes32(uint256(2));

    function setUp() public {
        owner = address(this);
        treasury = address(0xBEEF);
        couponRecipient = address(0xCAFE);

        usdc = new MockUSDC();
        carry = new MockCarryEngine();
        hedge = new MockHedgeManager();
        reserve = new ReserveFund(address(usdc), owner);
        feeCollector = new FeeCollector(address(usdc), treasury, owner);

        epoch = new EpochManager(
            address(usdc),
            address(reserve),
            address(feeCollector),
            address(carry),
            address(hedge),
            treasury,
            couponRecipient,
            owner
        );

        // Transfer reserve ownership to epoch manager for coverDeficit calls
        reserve.transferOwnership(address(epoch));
    }

    function test_initialState() public view {
        assertEq(epoch.getCurrentEpoch(), 0);
        assertFalse(epoch.isEpochReady());
    }

    function test_advanceEpoch() public {
        vm.warp(block.timestamp + 48 hours);
        assertTrue(epoch.isEpochReady());

        epoch.advanceEpoch();
        assertEq(epoch.getCurrentEpoch(), 1);
    }

    function test_advanceEpoch_revert_notReady() public {
        vm.expectRevert("epoch not ready");
        epoch.advanceEpoch();
    }

    function test_advanceEpoch_multiple() public {
        uint256 start = block.timestamp;
        vm.warp(start + 48 hours);
        epoch.advanceEpoch();
        assertEq(epoch.getCurrentEpoch(), 1);

        vm.warp(start + 96 hours);
        epoch.advanceEpoch();
        assertEq(epoch.getCurrentEpoch(), 2);
    }

    function test_addNote() public {
        epoch.addNote(NOTE_1, 100_000e6);
        assertEq(epoch.getActiveNoteCount(), 1);
        assertEq(epoch.totalNotionalOutstanding(), 100_000e6);
    }

    function test_removeNote() public {
        epoch.addNote(NOTE_1, 100_000e6);
        epoch.addNote(NOTE_2, 200_000e6);
        assertEq(epoch.getActiveNoteCount(), 2);

        epoch.removeNote(0, 100_000e6);
        assertEq(epoch.getActiveNoteCount(), 1);
        assertEq(epoch.totalNotionalOutstanding(), 200_000e6);
    }

    /// @notice INV-5: P1-P6 waterfall order ALWAYS respected
    function test_waterfall_p1_always_first() public {
        uint256 available = 10_000e6;
        usdc.mint(address(epoch), available);

        epoch.setPendingAmounts(8_000e6, 0, 5_000e6, 0);
        epoch.addNote(NOTE_1, TOTAL_NOTIONAL);

        epoch.distributeWaterfall();

        EpochManager.WaterfallResult memory result = epoch.getLastResult();
        assertEq(result.p1Paid, 8_000e6, "P1 should be fully paid");
        assertTrue(result.p1FullyPaid);
        assertLe(result.p3Paid, 2_000e6, "P3 gets at most the remainder");
    }

    /// @notice INV-5: NEVER P6 if P1 unpaid
    function test_waterfall_no_p6_if_p1_unpaid() public {
        uint256 available = 5_000e6;
        usdc.mint(address(epoch), available);

        epoch.setPendingAmounts(8_000e6, 0, 0, 0);

        epoch.distributeWaterfall();

        EpochManager.WaterfallResult memory result = epoch.getLastResult();
        assertFalse(result.p1FullyPaid);
        assertEq(result.p6Paid, 0, "P6 must be 0 when P1 is unpaid");
    }

    function test_waterfall_p6_when_p1_fully_paid() public {
        uint256 available = 20_000e6;
        usdc.mint(address(epoch), available);

        epoch.setPendingAmounts(5_000e6, 0, 2_000e6, 1_000e6);

        epoch.distributeWaterfall();

        EpochManager.WaterfallResult memory result = epoch.getLastResult();
        assertTrue(result.p1FullyPaid);
        assertEq(result.p1Paid, 5_000e6);
        assertEq(result.p3Paid, 2_000e6);
        assertEq(result.p4Paid, 1_000e6);
        // Remaining: 20000 - 5000 - 2000 - 1000 = 12000
        // P5 = 30% of 12000 = 3600
        // P6 = 12000 - 3600 = 8400
        assertEq(result.p5Paid, 3_600e6);
        assertEq(result.p6Paid, 8_400e6);
    }

    function test_waterfall_strict_order() public {
        uint256 available = 15_000e6;
        usdc.mint(address(epoch), available);

        epoch.setPendingAmounts(6_000e6, 4_000e6, 3_000e6, 2_000e6);

        epoch.distributeWaterfall();

        EpochManager.WaterfallResult memory result = epoch.getLastResult();
        assertEq(result.p1Paid, 6_000e6);
        assertEq(result.p2Paid, 4_000e6);
        assertEq(result.p3Paid, 3_000e6);
        assertEq(result.p4Paid, 2_000e6);
        assertEq(result.p5Paid, 0);
        assertEq(result.p6Paid, 0);
    }

    function test_waterfall_reserve_backup_for_p1() public {
        // Setup reserve with $5k
        reserve = new ReserveFund(address(usdc), owner);
        uint256 reserveAmount = 5_000e6;
        usdc.mint(owner, reserveAmount);
        usdc.approve(address(reserve), reserveAmount);
        reserve.deposit(reserveAmount);

        // Redeploy epoch with funded reserve
        epoch = new EpochManager(
            address(usdc), address(reserve), address(feeCollector),
            address(carry), address(hedge), treasury, couponRecipient, owner
        );
        reserve.transferOwnership(address(epoch));

        uint256 available = 3_000e6;
        usdc.mint(address(epoch), available);

        epoch.setPendingAmounts(5_000e6, 0, 0, 0);

        epoch.distributeWaterfall();

        EpochManager.WaterfallResult memory result = epoch.getLastResult();
        assertEq(result.p1Paid, 5_000e6, "P1 covered with reserve backup");
        assertTrue(result.p1FullyPaid);
    }

    function test_waterfall_haircut_on_carry() public {
        // Reserve at 0.5% (critical) -> 50% haircut
        reserve = new ReserveFund(address(usdc), owner);
        uint256 reserveAmount = 5_000e6; // 0.5% of $1M
        usdc.mint(owner, reserveAmount);
        usdc.approve(address(reserve), reserveAmount);
        reserve.deposit(reserveAmount);

        epoch = new EpochManager(
            address(usdc), address(reserve), address(feeCollector),
            address(carry), address(hedge), treasury, couponRecipient, owner
        );
        reserve.transferOwnership(address(epoch));

        epoch.addNote(NOTE_1, TOTAL_NOTIONAL);

        uint256 available = 20_000e6;
        usdc.mint(address(epoch), available);

        epoch.setPendingAmounts(0, 0, 10_000e6, 0);

        epoch.distributeWaterfall();

        EpochManager.WaterfallResult memory result = epoch.getLastResult();
        assertEq(result.p3Paid, 5_000e6, "P3 should be haircut to 50%");
    }

    function test_triggerRebalances() public {
        epoch.addNote(NOTE_1, 100_000e6);
        hedge.setDrift(NOTE_1, 600); // 6% > 5% threshold

        epoch.triggerRebalances();
        assertTrue(hedge.rebalanceCalled());
    }

    function test_getEpochStart() public view {
        uint256 start0 = epoch.getEpochStart(0);
        uint256 start1 = epoch.getEpochStart(1);
        uint256 start5 = epoch.getEpochStart(5);

        assertEq(start1 - start0, 48 hours);
        assertEq(start5 - start0, 5 * 48 hours);
    }

    function test_onlyOwner_advanceEpoch() public {
        vm.warp(block.timestamp + 48 hours);
        vm.prank(address(0xdead));
        vm.expectRevert();
        epoch.advanceEpoch();
    }

    function test_onlyOwner_distributeWaterfall() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        epoch.distributeWaterfall();
    }

    function test_waterfall_empty_no_revert() public {
        epoch.distributeWaterfall();

        EpochManager.WaterfallResult memory result = epoch.getLastResult();
        assertEq(result.p1Paid, 0);
        assertEq(result.p6Paid, 0);
    }

    /// @notice When reserve is below minimum (3%), 100% of remaining goes to reserve
    function test_waterfall_100pct_to_reserve_below_minimum() public {
        // Reserve at 2% (below 3% minimum)
        reserve = new ReserveFund(address(usdc), owner);
        uint256 reserveAmount = 20_000e6; // 2% of $1M
        usdc.mint(owner, reserveAmount);
        usdc.approve(address(reserve), reserveAmount);
        reserve.deposit(reserveAmount);

        epoch = new EpochManager(
            address(usdc), address(reserve), address(feeCollector),
            address(carry), address(hedge), treasury, couponRecipient, owner
        );
        reserve.transferOwnership(address(epoch));

        epoch.addNote(NOTE_1, TOTAL_NOTIONAL);

        uint256 available = 10_000e6;
        usdc.mint(address(epoch), available);

        // No P1-P4 pending, all goes to P5/P6
        epoch.setPendingAmounts(0, 0, 0, 0);

        epoch.distributeWaterfall();

        EpochManager.WaterfallResult memory result = epoch.getLastResult();
        // Since reserve < 3%, P5 should get 100% of remaining (not 30%)
        assertEq(result.p5Paid, available, "P5 should get 100% when reserve below minimum");
        assertEq(result.p6Paid, 0, "P6 should get 0 when all goes to reserve");
    }

    /// @notice When reserve is healthy (above 3%), 30% goes to reserve, rest to treasury
    function test_waterfall_30pct_to_reserve_above_minimum() public {
        // Reserve at 5% (above 3% minimum)
        reserve = new ReserveFund(address(usdc), owner);
        uint256 reserveAmount = 50_000e6; // 5% of $1M
        usdc.mint(owner, reserveAmount);
        usdc.approve(address(reserve), reserveAmount);
        reserve.deposit(reserveAmount);

        epoch = new EpochManager(
            address(usdc), address(reserve), address(feeCollector),
            address(carry), address(hedge), treasury, couponRecipient, owner
        );
        reserve.transferOwnership(address(epoch));

        epoch.addNote(NOTE_1, TOTAL_NOTIONAL);

        uint256 available = 10_000e6;
        usdc.mint(address(epoch), available);

        epoch.setPendingAmounts(0, 0, 0, 0);

        epoch.distributeWaterfall();

        EpochManager.WaterfallResult memory result = epoch.getLastResult();
        // Reserve healthy: P5 = 30% of 10000 = 3000
        assertEq(result.p5Paid, 3_000e6, "P5 should get 30% when reserve healthy");
        assertEq(result.p6Paid, 7_000e6, "P6 gets the rest");
    }
}
