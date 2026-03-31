// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { AutocallEngine, IPriceFeed } from "../src/core/AutocallEngine.sol";
import { XYieldVault } from "../src/core/XYieldVault.sol";
import { NoteToken } from "../src/core/NoteToken.sol";
import { State } from "../src/interfaces/IAutocallEngine.sol";
import { IHedgeManager } from "../src/interfaces/IHedgeManager.sol";
import { ICREConsumer, PricingResult } from "../src/interfaces/ICREConsumer.sol";
import { IIssuanceGate } from "../src/interfaces/IIssuanceGate.sol";
import { ICouponCalculator } from "../src/interfaces/ICouponCalculator.sol";
import { IVolOracle } from "../src/interfaces/IVolOracle.sol";
import { ICarryEngine } from "../src/interfaces/ICarryEngine.sol";
import { FeeCollector } from "../src/periphery/FeeCollector.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ================================================================
// Mocks (same as in AutocallEngine.t.sol but unified here)
// ================================================================

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function decimals() public pure override returns (uint8) { return 6; }
}

contract MockHedgeManager is IHedgeManager {
    uint256 public recoveredAmount = 100_000e6;
    function openHedge(bytes32, address[] calldata, uint256) external {}
    function closeHedge(bytes32) external returns (uint256) { return recoveredAmount; }
    function rebalance(bytes32) external {}
    function getDeltaDrift(bytes32) external pure returns (int256) { return 0; }
    function setRecoveredAmount(uint256 amount) external { recoveredAmount = amount; }
}

contract MockCREConsumer is ICREConsumer {
    mapping(bytes32 => PricingResult) public results;
    mapping(bytes32 => bool) public accepted;

    function setPricing(bytes32 noteId, PricingResult calldata result) external {
        results[noteId] = result;
        accepted[noteId] = true;
    }

    function fulfillPricing(bytes32, PricingResult calldata) external pure {}
    function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory) {
        require(accepted[noteId], "pricing not accepted");
        return results[noteId];
    }
}

contract MockIssuanceGate is IIssuanceGate {
    bool public approved = true;
    function checkIssuance(bytes32, uint256, address[] calldata) external view returns (bool, string memory) {
        return (approved, "");
    }
    function setApproved(bool _approved) external { approved = _approved; }
    function noteActivated(uint256) external {}
    function noteSettled(uint256) external {}
}

contract MockCouponCalculator is ICouponCalculator {
    function calculateCoupon(uint256, uint256, uint256) external pure returns (uint256, uint256, uint256) {
        return (700, 200, 900); // 7% base, 2% carry, 9% total
    }
    function calculateCouponAmount(uint256 notional, uint256 couponBps, uint256 obsIntervalDays)
        external pure returns (uint256) {
        return (notional * couponBps * obsIntervalDays) / (365 * 10_000);
    }
}

contract MockPriceFeed is IPriceFeed {
    mapping(bytes32 => int192) public prices;
    function setPrice(bytes32 feedId, int192 price) external { prices[feedId] = price; }
    function getLatestPrice(bytes32 feedId) external view returns (int192, uint32) {
        return (prices[feedId], uint32(block.timestamp));
    }
}

contract MockVolOracle is IVolOracle {
    function updateVols(address[] calldata, uint256[] calldata, uint256[] calldata) external {}
    function getVol(address) external pure returns (uint256) { return 4500; }
    function getAvgCorrelation(address[] calldata) external pure returns (uint256) { return 5000; }
    function getLastUpdate() external view returns (uint256) { return block.timestamp; }
}

contract MockCarryEngine is ICarryEngine {
    function collectCarry(bytes32) external pure returns (uint256, uint256) { return (0, 0); }
    function getTotalCarryRate() external pure returns (uint256) { return 900; }
    function getFundingRate() external pure returns (uint256) { return 550; }
    function getLendingRate() external pure returns (uint256) { return 350; }
}

// ================================================================
// End-to-End Test
// ================================================================

contract EndToEndTest is Test {
    MockUSDC public usdc;
    AutocallEngine public engine;
    XYieldVault public vault;
    NoteToken public noteToken;
    MockHedgeManager public hedge;
    MockCREConsumer public cre;
    MockIssuanceGate public gate;
    MockCouponCalculator public couponCalc;
    MockPriceFeed public priceFeed;
    MockVolOracle public volOracle;
    MockCarryEngine public carryEngine;

    address admin;
    address keeper = address(0xBEEF);
    address operator = address(0xFEED);
    address user = address(0x1234);

    address[] basket;
    bytes32 constant FEED_A = keccak256("FEED_A");
    bytes32 constant FEED_B = keccak256("FEED_B");
    bytes32 constant FEED_C = keccak256("FEED_C");

    function setUp() public {
        admin = address(this);
        usdc = new MockUSDC();
        hedge = new MockHedgeManager();
        cre = new MockCREConsumer();
        gate = new MockIssuanceGate();
        couponCalc = new MockCouponCalculator();
        priceFeed = new MockPriceFeed();
        volOracle = new MockVolOracle();
        carryEngine = new MockCarryEngine();
        noteToken = new NoteToken(admin);

        engine = new AutocallEngine(
            admin,
            address(usdc),
            address(hedge),
            address(cre),
            address(gate),
            address(couponCalc),
            address(priceFeed),
            address(volOracle),
            address(carryEngine),
            address(noteToken)
        );

        vault = new XYieldVault(admin, address(usdc), address(engine), address(noteToken));

        // Grant roles
        engine.grantRole(engine.KEEPER_ROLE(), keeper);
        engine.grantRole(engine.VAULT_ROLE(), address(vault));
        vault.grantRole(vault.OPERATOR_ROLE(), operator);
        noteToken.grantRole(noteToken.MINTER_ROLE(), address(vault));
        noteToken.grantRole(noteToken.BURNER_ROLE(), address(engine));

        // Configure 2-token basket (wQQQx + wSPYx — real testnet tokens)
        basket = new address[](2);
        basket[0] = address(0xA); // wQQQx
        basket[1] = address(0xB); // wSPYx

        engine.setFeedId(address(0xA), FEED_A);
        engine.setFeedId(address(0xB), FEED_B);

        priceFeed.setPrice(FEED_A, 450e8); // QQQ ~$450
        priceFeed.setPrice(FEED_B, 550e8); // SPY ~$550

        // Fund user
        usdc.mint(user, 100_000e6);
    }

    // ================================================================
    // Full lifecycle: deposit -> pricing -> activate -> autocall settle
    // ================================================================

    function test_e2e_deposit_to_autocall() public {
        uint256 depositAmount = 10_000e6;

        // --- Step 1: User requests deposit ---
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        uint256 requestId = vault.requestDeposit(depositAmount, user);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(vault)), depositAmount, "vault holds USDC");

        // --- Step 2: Operator creates note via engine ---
        vm.prank(address(vault));
        // Vault must call engine.createNote — but vault doesn't do this automatically.
        // The operator orchestrates: creates the note, prices it, then fulfills the deposit.

        // For the operator to call createNote, they need VAULT_ROLE.
        // In reality, an orchestrator contract would do this. For the test, let's
        // have the vault's operator call createNote directly.
        engine.grantRole(engine.VAULT_ROLE(), operator);

        vm.prank(operator);
        bytes32 noteId = engine.createNote(basket, depositAmount, user);
        assertEq(uint256(engine.getState(noteId)), uint256(State.Created));

        // --- Step 3: CRE pricing accepted ---
        PricingResult memory pricing = PricingResult({
            putPremiumBps: 900,
            kiProbabilityBps: 500,
            expectedKILossBps: 200,
            vegaBps: 100,
            inputsHash: keccak256("test")
        });
        cre.setPricing(noteId, pricing);

        int256[] memory initialPrices = new int256[](2);
        initialPrices[0] = 450e8; // QQQ
        initialPrices[1] = 550e8; // SPY

        vm.prank(keeper);
        engine.priceNote(noteId, initialPrices);
        assertEq(uint256(engine.getState(noteId)), uint256(State.Priced));

        // --- Step 4: Activate note (opens hedge) ---
        vm.prank(keeper);
        engine.activateNote(noteId);
        assertEq(uint256(engine.getState(noteId)), uint256(State.Active));

        // --- Step 5: Operator fulfills deposit in vault ---
        vm.prank(operator);
        vault.fulfillDeposit(requestId, noteId, basket);

        // --- Step 6: User claims deposit (gets NoteToken) ---
        vm.prank(user);
        uint256 tokenId = vault.claimDeposit(requestId);
        assertEq(noteToken.balanceOf(user, uint256(noteId)), depositAmount, "user holds NoteToken");

        // --- Step 7: Fund engine for coupon/settlement payments ---
        // The vault holds USDC but engine needs it to pay.
        // Transfer USDC from vault to engine (operator does this)
        usdc.mint(address(engine), depositAmount * 2); // Fund engine for coupons + settlement

        // --- Step 8: Observe -> Autocall (prices at 100%) ---
        engine.observe(noteId);
        // First obs: trigger = 100%, perf = 100% → autocall
        assertEq(uint256(engine.getState(noteId)), uint256(State.Settled));

        // --- Step 9: Verify user received payout ---
        uint256 userBal = usdc.balanceOf(user);
        // User should have: original balance - deposit + coupon + notional
        assertGt(userBal, 100_000e6, "user should profit from autocall");
    }

    // ================================================================
    // Full lifecycle: deposit -> 6 observations -> KI settlement (cash)
    // ================================================================

    function test_e2e_deposit_to_ki_cash_settle() public {
        uint256 depositAmount = 10_000e6;

        // Setup
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        uint256 requestId = vault.requestDeposit(depositAmount, user);
        vm.stopPrank();

        engine.grantRole(engine.VAULT_ROLE(), operator);

        // Create + Price + Activate
        vm.prank(operator);
        bytes32 noteId = engine.createNote(basket, depositAmount, user);

        PricingResult memory pricing = PricingResult({
            putPremiumBps: 900,
            kiProbabilityBps: 500,
            expectedKILossBps: 200,
            vegaBps: 100,
            inputsHash: keccak256("test")
        });
        cre.setPricing(noteId, pricing);

        int256[] memory initialPrices = new int256[](2);
        initialPrices[0] = 450e8; // QQQ
        initialPrices[1] = 550e8; // SPY

        vm.prank(keeper);
        engine.priceNote(noteId, initialPrices);
        vm.prank(keeper);
        engine.activateNote(noteId);

        vm.prank(operator);
        vault.fulfillDeposit(requestId, noteId, basket);
        vm.prank(user);
        vault.claimDeposit(requestId);

        // Fund engine
        usdc.mint(address(engine), depositAmount * 2);

        // Drop wSPYx to 40% of initial (550e8 -> 220e8)
        priceFeed.setPrice(FEED_B, 220e8); // 40% of 550

        // Run 6 observations with 30-day gaps
        uint256 t = block.timestamp;
        for (uint256 i = 0; i < 6; i++) {
            vm.warp(t + (i * 31 days));
            engine.observe(noteId);
        }

        assertEq(uint256(engine.getState(noteId)), uint256(State.KISettle));

        // User chooses cash settlement
        hedge.setRecoveredAmount(depositAmount); // hedge recovers full notional
        uint256 balBefore = usdc.balanceOf(user);
        vm.prank(user);
        engine.settleKI(noteId, false);

        assertEq(uint256(engine.getState(noteId)), uint256(State.Settled));

        // Cash = notional * worstPerf / BPS = 10000e6 * 4000 / 10000 = 4000e6
        uint256 payout = usdc.balanceOf(user) - balBefore;
        assertEq(payout, 4_000e6, "KI cash payout = 40% of notional");
    }

    // ================================================================
    // Full lifecycle: deposit -> coupon payments -> maturity settle (no KI)
    // ================================================================

    function test_e2e_deposit_to_maturity_with_coupons() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        uint256 requestId = vault.requestDeposit(depositAmount, user);
        vm.stopPrank();

        engine.grantRole(engine.VAULT_ROLE(), operator);

        vm.prank(operator);
        bytes32 noteId = engine.createNote(basket, depositAmount, user);

        PricingResult memory pricing = PricingResult({
            putPremiumBps: 900,
            kiProbabilityBps: 500,
            expectedKILossBps: 200,
            vegaBps: 100,
            inputsHash: keccak256("test")
        });
        cre.setPricing(noteId, pricing);

        int256[] memory prices = new int256[](2);
        prices[0] = 450e8;
        prices[1] = 550e8;

        vm.prank(keeper);
        engine.priceNote(noteId, prices);
        vm.prank(keeper);
        engine.activateNote(noteId);

        vm.prank(operator);
        vault.fulfillDeposit(requestId, noteId, basket);
        vm.prank(user);
        vault.claimDeposit(requestId);

        usdc.mint(address(engine), depositAmount * 3);

        // Set wSPYx to 80% — above coupon barrier (70%), below autocall (100%)
        priceFeed.setPrice(FEED_B, 440e8); // 80% of 550e8

        uint256 userBalBefore = usdc.balanceOf(user);
        uint256 t = block.timestamp;

        // 6 observations: coupons paid each time, no autocall
        for (uint256 i = 0; i < 6; i++) {
            vm.warp(t + (i * 31 days));
            engine.observe(noteId);
        }

        // At maturity: worst perf 80% >= 50% KI barrier → NoKISettle → Settled
        assertEq(uint256(engine.getState(noteId)), uint256(State.Settled));

        uint256 totalReceived = usdc.balanceOf(user) - userBalBefore;

        // Should receive: 6 coupons + notional
        // Coupon per obs = 10000e6 * 900bps * 30 / (365 * 10000) = ~7397e3 per obs
        // 6 coupons ~= 44383e3 = ~44e6
        // Total = ~10044e6
        assertGt(totalReceived, depositAmount, "should receive notional + coupons");
        assertGt(totalReceived, depositAmount + 40e6, "6 coupons should add up significantly");
    }

    // ================================================================
    // Deposit refund after deadline
    // ================================================================

    function test_e2e_deposit_refund_after_deadline() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        uint256 requestId = vault.requestDeposit(depositAmount, user);
        vm.stopPrank();

        uint256 userBalAfterDeposit = usdc.balanceOf(user);
        assertEq(userBalAfterDeposit, 90_000e6);

        // Warp past 24h deadline — no fulfill happened
        vm.warp(block.timestamp + 25 hours);

        // Anyone can trigger refund
        vault.refundDeposit(requestId);

        assertEq(usdc.balanceOf(user), 100_000e6, "full refund");
    }

    // ================================================================
    // Emergency pause mid-lifecycle
    // ================================================================

    function test_e2e_emergency_pause_and_resume() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.requestDeposit(depositAmount, user);
        vm.stopPrank();

        engine.grantRole(engine.VAULT_ROLE(), operator);

        vm.prank(operator);
        bytes32 noteId = engine.createNote(basket, depositAmount, user);

        PricingResult memory pricing = PricingResult({
            putPremiumBps: 900,
            kiProbabilityBps: 500,
            expectedKILossBps: 200,
            vegaBps: 100,
            inputsHash: keccak256("test")
        });
        cre.setPricing(noteId, pricing);

        int256[] memory prices = new int256[](2);
        prices[0] = 450e8;
        prices[1] = 550e8;

        vm.prank(keeper);
        engine.priceNote(noteId, prices);
        vm.prank(keeper);
        engine.activateNote(noteId);

        // Emergency pause
        engine.emergencyPause(noteId);
        assertEq(uint256(engine.getState(noteId)), uint256(State.EmergencyPaused));

        // Cannot observe while paused
        vm.expectRevert();
        engine.observe(noteId);

        // Resume
        engine.emergencyResume(noteId);
        assertEq(uint256(engine.getState(noteId)), uint256(State.Active));

        // Can observe again
        usdc.mint(address(engine), depositAmount * 2);
        engine.observe(noteId);
        // Autocall at 100%
        assertEq(uint256(engine.getState(noteId)), uint256(State.Settled));
    }

    // ================================================================
    // Mixed scenario: miss coupons then autocall with memory
    // ================================================================

    function test_e2e_miss_coupons_then_recover_autocall() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.requestDeposit(depositAmount, user);
        vm.stopPrank();

        engine.grantRole(engine.VAULT_ROLE(), operator);

        vm.prank(operator);
        bytes32 noteId = engine.createNote(basket, depositAmount, user);

        PricingResult memory pricing = PricingResult({
            putPremiumBps: 900, kiProbabilityBps: 500,
            expectedKILossBps: 200, vegaBps: 100, inputsHash: keccak256("test")
        });
        cre.setPricing(noteId, pricing);

        int256[] memory prices = new int256[](2);
        prices[0] = 450e8; prices[1] = 550e8;

        vm.prank(keeper);
        engine.priceNote(noteId, prices);
        vm.prank(keeper);
        engine.activateNote(noteId);

        usdc.mint(address(engine), depositAmount * 3);

        // Obs 1-3: market crashes — miss coupons (60% perf)
        priceFeed.setPrice(FEED_B, 330e8); // 60% of 550e8

        uint256 t = block.timestamp;
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(t + (i * 31 days));
            engine.observe(noteId);
            assertEq(uint256(engine.getState(noteId)), uint256(State.Active));
        }

        // Check memory accumulated
        (,,,,, uint256 memCoupon,,,) = engine.getNote(noteId);
        assertGt(memCoupon, 0, "3 missed coupons accumulated");

        // Obs 4: market recovers — autocall at 100%
        priceFeed.setPrice(FEED_B, 550e8); // back to 100%
        vm.warp(t + (3 * 31 days));

        uint256 balBefore = usdc.balanceOf(user);
        engine.observe(noteId);

        assertEq(uint256(engine.getState(noteId)), uint256(State.Settled));

        // User gets: current coupon + 3 missed memory coupons + notional
        uint256 received = usdc.balanceOf(user) - balBefore;
        assertGt(received, depositAmount, "notional + coupons + memory");
    }

    // ================================================================
    // Fee collection on deposit
    // ================================================================

    function test_e2e_fees_collected_on_deposit() public {
        // Deploy a real FeeCollector
        address treasury = address(0xDEAD);

        // Import FeeCollector
        FeeCollector fc = new FeeCollector(address(usdc), treasury, admin);

        // Set fee collector on vault
        vault.setFeeCollector(address(fc));

        uint256 depositAmount = 10_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        uint256 requestId = vault.requestDeposit(depositAmount, user);
        vm.stopPrank();

        engine.grantRole(engine.VAULT_ROLE(), operator);

        vm.prank(operator);
        bytes32 noteId = engine.createNote(basket, depositAmount, user);

        PricingResult memory pricing = PricingResult({
            putPremiumBps: 900, kiProbabilityBps: 500,
            expectedKILossBps: 200, vegaBps: 100, inputsHash: keccak256("test")
        });
        cre.setPricing(noteId, pricing);

        int256[] memory prices = new int256[](2);
        prices[0] = 450e8; prices[1] = 550e8;

        vm.prank(keeper);
        engine.priceNote(noteId, prices);
        vm.prank(keeper);
        engine.activateNote(noteId);

        vm.prank(operator);
        vault.fulfillDeposit(requestId, noteId, basket);

        vm.prank(user);
        vault.claimDeposit(requestId);

        // Embedded fee = 0.5% of 10000 = 50
        // Origination fee = 0.1% of 10000 = 10
        // Total fees = 60
        uint256 expectedFees = 60e6;
        assertEq(usdc.balanceOf(treasury), expectedFees, "treasury received fees");

        // Engine received net amount
        uint256 engineBal = usdc.balanceOf(address(engine));
        assertEq(engineBal, depositAmount - expectedFees, "engine received net amount");
    }
}
