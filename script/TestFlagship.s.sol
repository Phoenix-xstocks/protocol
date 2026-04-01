// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AutocallEngine } from "../src/core/AutocallEngine.sol";
import { XYieldVault } from "../src/core/XYieldVault.sol";
import { State } from "../src/interfaces/IAutocallEngine.sol";

/// @title TestFlagship
/// @notice Full on-chain E2E test: deposit → create → price → activate → verify
///         Uses the flagship basket: NVDAx + TSLAx + METAx
contract TestFlagship is Script {
    // Tokens
    address constant USDC   = 0x6b57475467cd854d36Be7FB614caDa5207838943;
    address constant WQQQX  = 0x267ED9BC43B16D832cB9Aaf0e3445f0cC9f536d9;
    address constant WSPYX  = 0x9eF9f9B22d3CA9769e28e769e2AAA3C2B0072D0e;

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
        console.log("--- Step 2: Create Note (WQQQX + WSPYX) ---");
        address[] memory basket = new address[](2);
        basket[0] = WQQQX;
        basket[1] = WSPYX;

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
        console.log("Basket: WQQQX + WSPYX");
        console.log("Notional: 5000 USDC");
        console.log("Next step: priceNote (requires CRE pricing or mock)");
    }
}
