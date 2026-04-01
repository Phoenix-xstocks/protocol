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
    address constant NVDAx  = 0x3EfB67e01d5Ab3dd37dBb34D8a8c09D0682Bfc4E;
    address constant TSLAx  = 0x2a968432b2BC26dA460A0B7262414552288C894E;
    address constant METAx  = 0x7EA9266A024e168341827a9c4621EC5b16cda65a;
    address constant ENGINE  = 0x2Abb3C917aEaC67A9aa3f375A6D4F1Ca30B5735e;
    address constant VAULT   = 0x194AaCC47fb0c89C467331478FcE9B529E8f6385;

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
        address[] memory assets = new address[](3);
        assets[0] = NVDAx; assets[1] = TSLAx; assets[2] = METAx;
        uint256[] memory vols = new uint256[](3);
        vols[0] = 5500; vols[1] = 6000; vols[2] = 4000;
        uint256[] memory corrs = new uint256[](3);
        corrs[0] = 5500; corrs[1] = 4800; corrs[2] = 5200;
        vol.updateVols(assets, vols, corrs);

        // Setup feed IDs
        engine.setFeedId(NVDAx, 0xb1073854ed24cbc755dc527418f52b7d271f6cc967bbf8d8129112b18860a593);
        engine.setFeedId(TSLAx, 0x16dad506d7db8da01c87581c87ca897a012a153557d4d578c3b9c9e1bc0632f1);
        engine.setFeedId(METAx, 0x78a3e3b8e676a8f73c439f5d749737034b139bbbe899ba5775216fba596607fe);

        // 1. Deposit
        console.log("[1/5] Deposit 500 USDC");
        usdc.approve(VAULT, 500e6);
        vault.requestDeposit(500e6, deployer);

        // 2. Create note (net after 0.6% fees: 500 - 3 = 497)
        console.log("[2/5] Create note");
        address[] memory basket = new address[](3);
        basket[0] = NVDAx; basket[1] = TSLAx; basket[2] = METAx;
        uint256 netAmount = 500e6 - (500e6 * 60 / 10000); // 0.6% fees
        bytes32 noteId = engine.createNote(basket, netAmount, deployer);
        console.log("  State:", uint256(engine.getState(noteId)));

        // 3. Fulfill + Claim
        console.log("[3/5] Fulfill + Claim");
        vault.fulfillDeposit(0, noteId, basket);
        vault.claimDeposit(0);
        console.log("  Engine USDC:", usdc.balanceOf(ENGINE) / 1e6);

        // 4. Price
        console.log("[4/5] Price (1106 bps)");
        int256[] memory initPrices = new int256[](3);
        initPrices[0] = 130e8; initPrices[1] = 280e8; initPrices[2] = 580e8;
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
