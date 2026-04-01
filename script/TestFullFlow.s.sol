// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AutocallEngine } from "../src/core/AutocallEngine.sol";
import { XYieldVault } from "../src/core/XYieldVault.sol";
import { VolOracle } from "../src/pricing/VolOracle.sol";
import { State } from "../src/interfaces/IAutocallEngine.sol";

contract TestFullFlow is Script {
    address constant USDC   = 0x6b57475467cd854d36Be7FB614caDa5207838943;
    address constant WQQQX  = 0x267ED9BC43B16D832cB9Aaf0e3445f0cC9f536d9;
    address constant WSPYX  = 0x9eF9f9B22d3CA9769e28e769e2AAA3C2B0072D0e;
    address constant ENGINE  = 0x9AE3640d07470db79D93f493d27B8C14a04Addd3;
    address constant VAULT   = 0x11Da586be00d92749f0abA4e5F54175df0fccf07;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        AutocallEngine engine = AutocallEngine(ENGINE);
        XYieldVault vault = XYieldVault(VAULT);
        IERC20 usdc = IERC20(USDC);

        console.log("=== FULL FLOW: DEPOSIT -> ACTIVATE ===");
        console.log("USDC:", usdc.balanceOf(deployer) / 1e6);

        vm.startBroadcast(pk);

        // 0. Setup VolOracle
        VolOracle vol = VolOracle(address(engine.volOracle()));
        address[] memory assets = new address[](2);
        assets[0] = WQQQX; assets[1] = WSPYX;
        uint256[] memory vols = new uint256[](2);
        vols[0] = 3500; vols[1] = 3000; // index vols lower than single stocks
        uint256[] memory corrs = new uint256[](1);
        corrs[0] = 8500; // high correlation between indices
        vol.updateVols(assets, vols, corrs);

        // Setup feed IDs (QQQX/USD and SPYX/USD)
        engine.setFeedId(WQQQX, 0x178a6f73a5aede9d0d682e86b0047c9f333ed0efe5c6537ca937565219c4054d);
        engine.setFeedId(WSPYX, 0x2817b78438c769357182c04346fddaad1178c82f4048828fe0997c3c64624e14);

        // 1. Deposit
        console.log("[1/5] Deposit 500 USDC");
        usdc.approve(VAULT, 200e6);
        vault.requestDeposit(200e6, deployer);

        // 2. Create note (net after 0.6% fees: 500 - 3 = 497)
        console.log("[2/5] Create note");
        address[] memory basket = new address[](2);
        basket[0] = WQQQX; basket[1] = WSPYX;
        uint256 netAmount = 200e6 - (200e6 * 60 / 10000); // 0.6% fees
        bytes32 noteId = engine.createNote(basket, netAmount, deployer);
        console.log("  State:", uint256(engine.getState(noteId)));

        // 3. Fulfill + Claim
        console.log("[3/5] Fulfill + Claim");
        vault.fulfillDeposit(0, noteId, basket);
        vault.claimDeposit(0);
        console.log("  Engine USDC:", usdc.balanceOf(ENGINE) / 1e6);

        // 4. Price
        console.log("[4/5] Price (1106 bps)");
        int256[] memory initPrices = new int256[](2);
        initPrices[0] = 2557e6; initPrices[1] = 62250e6; // QQQ $25.57, SPY $622.50 (Tydro oracle prices)
        engine.priceNoteDirect(noteId, initPrices, 1106);
        console.log("  State:", uint256(engine.getState(noteId)));

        // 5. ACTIVATE
        console.log("[5/5] ACTIVATE");
        engine.activateNote(noteId);
        console.log("  State:", uint256(engine.getState(noteId)));

        vm.stopBroadcast();

        if (engine.getState(noteId) == State.Active) {
            console.log("");
            console.log("=== NOTE IS ACTIVE !!! ===");
            console.log("Flow complete: deposit -> price -> activate");
        }
    }
}
