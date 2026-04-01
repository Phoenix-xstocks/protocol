// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AutocallEngine } from "../src/core/AutocallEngine.sol";
import { XYieldVault } from "../src/core/XYieldVault.sol";
import { ChainlinkPriceFeed } from "../src/integrations/ChainlinkPriceFeed.sol";
import { VolOracle } from "../src/pricing/VolOracle.sol";
import { State } from "../src/interfaces/IAutocallEngine.sol";

/// @title TestFullFlow
/// @notice Complete on-chain flow: deposit → price → activate → verify
///         Uses priceNoteDirect() to bypass CRE on testnet.
contract TestFullFlow is Script {
    address constant USDC   = 0x6b57475467cd854d36Be7FB614caDa5207838943;
    address constant NVDAx  = 0x3EfB67e01d5Ab3dd37dBb34D8a8c09D0682Bfc4E;
    address constant TSLAx  = 0x2a968432b2BC26dA460A0B7262414552288C894E;
    address constant METAx  = 0x7EA9266A024e168341827a9c4621EC5b16cda65a;

    address constant ENGINE  = 0x65cBd62cF76b4B2fE19d0e199A06550f74d5bB4e;
    address constant VAULT   = 0x72470eDB59e433E33FB7a70fE97eF0291bf25D6E;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        AutocallEngine engine = AutocallEngine(ENGINE);
        XYieldVault vault = XYieldVault(VAULT);
        IERC20 usdc = IERC20(USDC);

        console.log("=== FULL FLOW TEST ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        // --- 1. Deposit ---
        console.log("");
        console.log("[1/5] Depositing 2000 USDC...");
        usdc.approve(VAULT, 2000e6);
        uint256 reqId = vault.requestDeposit(2000e6, deployer);

        // --- 2. Create note ---
        console.log("[2/5] Creating note (NVDAx + TSLAx + METAx)...");
        address[] memory basket = new address[](3);
        basket[0] = NVDAx;
        basket[1] = TSLAx;
        basket[2] = METAx;
        bytes32 noteId = engine.createNote(basket, 2000e6, deployer);

        // --- 3. Fulfill + Claim ---
        console.log("[3/5] Fulfilling and claiming deposit...");
        vault.fulfillDeposit(reqId, noteId, basket);
        vault.claimDeposit(reqId);

        console.log("  Engine USDC:", usdc.balanceOf(ENGINE) / 1e6);
        require(engine.getState(noteId) == State.Created, "should be Created");

        // --- 4. Price note (testnet direct — bypass CRE) ---
        console.log("[4/5] Pricing note (premium=1106 bps, testnet mode)...");
        int256[] memory initialPrices = new int256[](3);
        initialPrices[0] = 130e8;  // NVDA $130
        initialPrices[1] = 280e8;  // TSLA $280
        initialPrices[2] = 580e8;  // META $580

        engine.priceNoteDirect(noteId, initialPrices, 1106);
        require(engine.getState(noteId) == State.Priced, "should be Priced");
        console.log("  State: Priced");

        // --- 5. Activate (opens hedge) ---
        console.log("[5/5] Activating note...");

        // Need to approve engine to let HedgeManager pull USDC
        // But HedgeManager's openHedge will call swapper which needs real xStocks
        // On testnet with mock adapters, this will revert at the swap level
        // So we skip activation for now and just verify pricing worked

        console.log("  Note state:", uint256(engine.getState(noteId)));
        console.log("  Note count:", engine.getNoteCount());

        vm.stopBroadcast();

        console.log("");
        console.log("=== FLOW TEST COMPLETE ===");
        console.log("Achieved: deposit -> create -> claim -> price (testnet direct)");
        console.log("Blocked at: activate (needs real Nado/Tydro/1inch)");
    }
}
