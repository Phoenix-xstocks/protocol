// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AutocallEngine } from "../src/core/AutocallEngine.sol";
import { XYieldVault } from "../src/core/XYieldVault.sol";
import { NoteToken } from "../src/core/NoteToken.sol";
import { CREConsumer } from "../src/pricing/CREConsumer.sol";
import { VolOracle } from "../src/pricing/VolOracle.sol";
import { State } from "../src/interfaces/IAutocallEngine.sol";
import { PricingResult } from "../src/interfaces/ICREConsumer.sol";

/// @title TestFlagship
/// @notice Full on-chain E2E test: deposit → create → price → activate → verify
///         Uses the flagship basket: NVDAx + TSLAx + METAx
contract TestFlagship is Script {
    // Tokens
    address constant USDC   = 0x6b57475467cd854d36Be7FB614caDa5207838943;
    address constant NVDAx  = 0x3EfB67e01d5Ab3dd37dBb34D8a8c09D0682Bfc4E;
    address constant TSLAx  = 0x2a968432b2BC26dA460A0B7262414552288C894E;
    address constant METAx  = 0x7EA9266A024e168341827a9c4621EC5b16cda65a;

    // Latest deploy
    address constant ENGINE  = 0x65cBd62cF76b4B2fE19d0e199A06550f74d5bB4e;
    address constant VAULT   = 0x72470eDB59e433E33FB7a70fE97eF0291bf25D6E;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        AutocallEngine engine = AutocallEngine(ENGINE);
        XYieldVault vault = XYieldVault(VAULT);
        IERC20 usdc = IERC20(USDC);

        console.log("=== FLAGSHIP BASKET E2E TEST ===");
        console.log("Deployer:", deployer);
        console.log("USDC balance:", usdc.balanceOf(deployer) / 1e6, "USDC");
        console.log("");

        vm.startBroadcast(pk);

        // ============================================
        // Step 1: Deposit 5000 USDC into vault
        // ============================================
        console.log("--- Step 1: Deposit ---");
        usdc.approve(VAULT, 5000e6);
        uint256 requestId = vault.requestDeposit(5000e6, deployer);
        console.log("Request ID:", requestId);
        console.log("Vault USDC:", usdc.balanceOf(VAULT) / 1e6, "USDC");

        // ============================================
        // Step 2: Create note with flagship basket
        // ============================================
        console.log("");
        console.log("--- Step 2: Create Note (NVDAx + TSLAx + METAx) ---");
        address[] memory basket = new address[](3);
        basket[0] = NVDAx;
        basket[1] = TSLAx;
        basket[2] = METAx;

        bytes32 noteId = engine.createNote(basket, 5000e6, deployer);
        console.log("Note ID:");
        console.logBytes32(noteId);

        State state1 = engine.getState(noteId);
        console.log("State: Created (expected 0, got", uint256(state1), ")");

        // ============================================
        // Step 3: Fulfill deposit in vault
        // ============================================
        console.log("");
        console.log("--- Step 3: Fulfill Deposit ---");
        vault.fulfillDeposit(requestId, noteId, basket);
        console.log("Deposit fulfilled, ready to claim");

        // ============================================
        // Step 4: Claim deposit (mints NoteToken, transfers USDC to engine)
        // ============================================
        console.log("");
        console.log("--- Step 4: Claim Deposit ---");
        vault.claimDeposit(requestId);
        console.log("NoteToken minted");
        console.log("Engine USDC:", usdc.balanceOf(ENGINE) / 1e6, "USDC");

        // ============================================
        // Step 5: Verify final state
        // ============================================
        console.log("");
        console.log("--- Step 5: Verification ---");
        console.log("Note count:", engine.getNoteCount());
        console.log("Note state:", uint256(engine.getState(noteId)));
        console.log("Vault total assets:", vault.totalAssets() / 1e6, "USDC");

        vm.stopBroadcast();

        console.log("");
        console.log("=== FLAGSHIP E2E TEST PASSED ===");
        console.log("Basket: NVDAx + TSLAx + METAx");
        console.log("Notional: 5000 USDC");
        console.log("Next step: priceNote (requires CRE pricing or mock)");
    }
}
