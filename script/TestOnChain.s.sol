// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AutocallEngine } from "../src/core/AutocallEngine.sol";
import { XYieldVault } from "../src/core/XYieldVault.sol";
import { State } from "../src/interfaces/IAutocallEngine.sol";

/// @title TestOnChain
/// @notice Smoke test: deposits real USDC, creates a note, verifies state.
///         Run: forge script script/TestOnChain.s.sol --rpc-url $RPC --broadcast
contract TestOnChain is Script {
    address constant USDC = 0x6b57475467cd854d36Be7FB614caDa5207838943;
    address constant WQQQX = 0x267ED9BC43B16D832cB9Aaf0e3445f0cC9f536d9;
    address constant WSPYX = 0x9eF9f9B22d3CA9769e28e769e2AAA3C2B0072D0e;

    // Latest deploy addresses
    address constant ENGINE = 0xB6a9BE9f9BD4C690539f4Df671184efce3fc22C2;
    address constant VAULT = 0x243f098E589118fB0F5e8a6f13f987Da170b5D3a;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("=== On-Chain Smoke Test ===");
        console.log("Deployer:", deployer);

        AutocallEngine engine = AutocallEngine(ENGINE);
        XYieldVault vault = XYieldVault(VAULT);
        IERC20 usdc = IERC20(USDC);

        // Check balances
        uint256 usdcBal = usdc.balanceOf(deployer);
        console.log("USDC balance:", usdcBal / 1e6, "USDC");
        require(usdcBal >= 1000e6, "need at least 1000 USDC");

        vm.startBroadcast(pk);

        // 1. Approve + Deposit
        usdc.approve(VAULT, 1000e6);
        uint256 requestId = vault.requestDeposit(1000e6, deployer);
        console.log("Deposit request ID:", requestId);

        // 2. Create note with real basket
        address[] memory basket = new address[](2);
        basket[0] = WQQQX;
        basket[1] = WSPYX;
        bytes32 noteId = engine.createNote(basket, 1000e6, deployer);
        console.log("Note created, ID:");
        console.logBytes32(noteId);

        // 3. Verify state
        State state = engine.getState(noteId);
        require(state == State.Created, "note should be in Created state");
        console.log("Note state: Created (0)");

        // 4. Verify vault received USDC
        uint256 vaultBal = usdc.balanceOf(VAULT);
        console.log("Vault USDC:", vaultBal / 1e6, "USDC");

        // 5. Verify note count
        uint256 noteCount = engine.getNoteCount();
        console.log("Total notes:", noteCount);

        vm.stopBroadcast();

        console.log("");
        console.log("=== SMOKE TEST PASSED ===");
    }
}
