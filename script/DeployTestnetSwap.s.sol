// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { TestnetSwap } from "../src/integrations/TestnetSwap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMintable {
    function mint(address to, uint256 amount) external;
}

/// @title DeployTestnetSwap
/// @notice Deploy TestnetSwap, set prices, add liquidity for all xStocks
contract DeployTestnetSwap is Script {
    address constant USDC   = 0x6b57475467cd854d36Be7FB614caDa5207838943;
    address constant NVDAx  = 0x3EfB67e01d5Ab3dd37dBb34D8a8c09D0682Bfc4E;
    address constant TSLAx  = 0x2a968432b2BC26dA460A0B7262414552288C894E;
    address constant METAx  = 0x7EA9266A024e168341827a9c4621EC5b16cda65a;
    address constant AAPLx  = 0x556bF69F08c7f712B1E79F1486a080165Dc7949c;
    address constant MSFTx  = 0xB13A4f9D68cd1BaD482940D30b7029DBe746c153;
    address constant AMZNx  = 0xe9429944c6f7ba23aAbfc1F9D6556CcDC2a4059E;
    address constant GOOGLx = 0x0023F314f5E79db2C8d6b263760a3191A0F13d15;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        // 1. Deploy TestnetSwap
        TestnetSwap swap = new TestnetSwap(USDC, deployer);
        console.log("TestnetSwap:", address(swap));

        // 2. Set prices (USDC 6 decimals)
        swap.setPrice(NVDAx,  130e6);  // NVDA  $130
        swap.setPrice(TSLAx,  280e6);  // TSLA  $280
        swap.setPrice(METAx,  580e6);  // META  $580
        swap.setPrice(AAPLx,  230e6);  // AAPL  $230
        swap.setPrice(MSFTx,  430e6);  // MSFT  $430
        swap.setPrice(AMZNx,  200e6);  // AMZN  $200
        swap.setPrice(GOOGLx, 175e6);  // GOOGL $175
        console.log("Prices set for 7 xStocks");

        // 3. Mint xStocks to deployer (we own them, they're mintable)
        uint256 liq = 100_000 ether; // 100k tokens each
        IMintable(NVDAx).mint(deployer, liq);
        IMintable(TSLAx).mint(deployer, liq);
        IMintable(METAx).mint(deployer, liq);

        // 4. Add xStock liquidity (we can mint these, we deployed them)
        IERC20(NVDAx).approve(address(swap), liq);
        swap.addLiquidity(NVDAx, liq);

        IERC20(TSLAx).approve(address(swap), liq);
        swap.addLiquidity(TSLAx, liq);

        IERC20(METAx).approve(address(swap), liq);
        swap.addLiquidity(METAx, liq);

        // 5. Add USDC liquidity from our wallet (can't mint USDC)
        uint256 usdcBal = IERC20(USDC).balanceOf(deployer);
        uint256 usdcLiq = usdcBal > 5000e6 ? 5000e6 : usdcBal / 2;
        IERC20(USDC).approve(address(swap), usdcLiq);
        swap.addLiquidity(USDC, usdcLiq);

        console.log("Liquidity: 100k xStocks each +", usdcLiq / 1e6, "USDC");

        // 6. Test swap: 100 USDC -> NVDAx
        IERC20(USDC).approve(address(swap), 100e6);
        uint256 out = swap.swap(USDC, NVDAx, 100e6);
        console.log("Test: 100 USDC -> NVDAx =", out / 1e15, "* 1e-3 tokens");

        // 7. Test reverse: NVDAx -> USDC
        IERC20(NVDAx).approve(address(swap), out);
        uint256 usdcBack = swap.swap(NVDAx, USDC, out);
        console.log("Test: NVDAx -> USDC =", usdcBack / 1e6, "USDC");

        vm.stopBroadcast();

        console.log("");
        console.log("=== TESTNET SWAP DEPLOYED ===");
        console.log("Address:", address(swap));
        console.log("Implements IOneInchSwapper - plug into HedgeManager");
    }
}
