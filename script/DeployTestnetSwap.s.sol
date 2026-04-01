// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { TestnetSwap } from "../src/integrations/TestnetSwap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DeployTestnetSwap
/// @notice Deploy TestnetSwap, set prices, add liquidity for official xStock tokens (WQQQX, WSPYX)
contract DeployTestnetSwap is Script {
    address constant USDC   = 0x6b57475467cd854d36Be7FB614caDa5207838943;
    address constant WQQQX  = 0x267ED9BC43B16D832cB9Aaf0e3445f0cC9f536d9;
    address constant WSPYX  = 0x9eF9f9B22d3CA9769e28e769e2AAA3C2B0072D0e;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        // 1. Deploy TestnetSwap
        TestnetSwap swap = new TestnetSwap(USDC, deployer);
        console.log("TestnetSwap:", address(swap));

        // 2. Set prices (USDC 6 decimals)
        swap.setPrice(WQQQX, 480e6);  // QQQ ~$480
        swap.setPrice(WSPYX, 560e6);  // SPY ~$560
        console.log("Prices set for WQQQX and WSPYX");

        // 3. Add xStock liquidity from deployer wallet (official tokens, no minting)
        uint256 qqqBal = IERC20(WQQQX).balanceOf(deployer);
        uint256 spyBal = IERC20(WSPYX).balanceOf(deployer);
        console.log("WQQQX balance:", qqqBal / 1e18, "tokens");
        console.log("WSPYX balance:", spyBal / 1e18, "tokens");

        if (qqqBal > 0) {
            IERC20(WQQQX).approve(address(swap), qqqBal);
            swap.addLiquidity(WQQQX, qqqBal);
        }

        if (spyBal > 0) {
            IERC20(WSPYX).approve(address(swap), spyBal);
            swap.addLiquidity(WSPYX, spyBal);
        }

        // 4. Add USDC liquidity from deployer wallet
        uint256 usdcBal = IERC20(USDC).balanceOf(deployer);
        uint256 usdcLiq = usdcBal > 5000e6 ? 5000e6 : usdcBal / 2;
        IERC20(USDC).approve(address(swap), usdcLiq);
        swap.addLiquidity(USDC, usdcLiq);

        console.log("USDC liquidity added:", usdcLiq / 1e6, "USDC");

        vm.stopBroadcast();

        console.log("");
        console.log("=== TESTNET SWAP DEPLOYED ===");
        console.log("Address:", address(swap));
        console.log("Implements IOneInchSwapper - plug into HedgeManager");
    }
}
