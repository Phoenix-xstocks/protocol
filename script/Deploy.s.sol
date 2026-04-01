// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";

// Core
import { AutocallEngine } from "../src/core/AutocallEngine.sol";
import { NoteToken } from "../src/core/NoteToken.sol";
import { XYieldVault } from "../src/core/XYieldVault.sol";

// Pricing
import { VolOracle } from "../src/pricing/VolOracle.sol";
import { OptionPricer } from "../src/pricing/OptionPricer.sol";
import { CREConsumer } from "../src/pricing/CREConsumer.sol";
import { IssuanceGate } from "../src/pricing/IssuanceGate.sol";
import { CouponCalculator } from "../src/pricing/CouponCalculator.sol";

// Hedge
import { HedgeManager } from "../src/hedge/HedgeManager.sol";
import { CarryEngine } from "../src/hedge/CarryEngine.sol";

// Integrations
import { NadoAdapter } from "../src/integrations/NadoAdapter.sol";
import { TydroAdapter } from "../src/integrations/TydroAdapter.sol";
import { OneInchSwapper } from "../src/integrations/OneInchSwapper.sol";
import { PythAdapter } from "../src/integrations/PythAdapter.sol";

// Periphery
import { ReserveFund } from "../src/periphery/ReserveFund.sol";
import { EpochManager } from "../src/periphery/EpochManager.sol";
import { ProtocolStats } from "../src/periphery/ProtocolStats.sol";
import { FeeCollector } from "../src/periphery/FeeCollector.sol";

/// @title Deploy
/// @notice Full protocol deployment to Ink Sepolia testnet.
///         Uses mock addresses for external protocols (Nado, Tydro, 1inch, Sablier, Chainlink)
///         until real testnet addresses are confirmed.
contract Deploy is Script {
    // Ink Sepolia testnet token addresses
    address constant USDC = 0x6b57475467cd854d36Be7FB614caDa5207838943;
    address constant wQQQx = 0x267ED9BC43B16D832cB9Aaf0e3445f0cC9f536d9;
    address constant wSPYx = 0x9eF9f9B22d3CA9769e28e769e2AAA3C2B0072D0e;

    // External protocol placeholders (to be updated with real addresses)
    address constant MOCK_NADO_PERP = address(0x1001);
    address constant MOCK_TYDRO_POOL = address(0x1002);
    address constant MOCK_1INCH_ROUTER = address(0x1003);
    // Pyth on Ink Sepolia
    address constant PYTH = 0x2880aB155794e7179c9eE2e38200202908C17B43;

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address treasury = deployer; // treasury = deployer for testnet

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPk);

        // ---- 1. Pricing layer (no protocol deps) ----
        VolOracle volOracle = new VolOracle(deployer);
        console.log("VolOracle:", address(volOracle));

        OptionPricer optionPricer = new OptionPricer(address(volOracle), deployer);
        console.log("OptionPricer:", address(optionPricer));

        CREConsumer creConsumer = new CREConsumer(address(1), address(optionPricer), deployer);
        console.log("CREConsumer:", address(creConsumer));

        CouponCalculator couponCalculator = new CouponCalculator();
        console.log("CouponCalculator:", address(couponCalculator));

        // ---- 2. Integration adapters ----
        NadoAdapter nado = new NadoAdapter(MOCK_NADO_PERP, USDC, deployer);
        console.log("NadoAdapter:", address(nado));

        TydroAdapter tydro = new TydroAdapter(MOCK_TYDRO_POOL, USDC, deployer);
        console.log("TydroAdapter:", address(tydro));

        OneInchSwapper swapper = new OneInchSwapper(MOCK_1INCH_ROUTER, deployer);
        console.log("OneInchSwapper:", address(swapper));

        PythAdapter priceFeed = new PythAdapter(PYTH, deployer);
        console.log("PythAdapter:", address(priceFeed));

        // ---- 3. Hedge layer ----
        HedgeManager hedgeManager = new HedgeManager(
            address(nado), address(tydro), address(swapper), USDC, deployer
        );
        console.log("HedgeManager:", address(hedgeManager));

        CarryEngine carryEngine = new CarryEngine(address(nado), address(tydro), USDC, deployer);
        console.log("CarryEngine:", address(carryEngine));

        // ---- 4. Periphery ----
        ReserveFund reserveFund = new ReserveFund(USDC, deployer);
        console.log("ReserveFund:", address(reserveFund));

        FeeCollector feeCollector = new FeeCollector(USDC, treasury, deployer);
        console.log("FeeCollector:", address(feeCollector));

        IssuanceGate issuanceGate = new IssuanceGate(
            address(creConsumer), address(hedgeManager), address(reserveFund), deployer
        );
        console.log("IssuanceGate:", address(issuanceGate));

        EpochManager epochManager = new EpochManager(
            USDC, address(reserveFund), address(feeCollector),
            address(carryEngine), address(hedgeManager), treasury, deployer, deployer
        );
        console.log("EpochManager:", address(epochManager));

        // ---- 5. Core ----
        NoteToken noteToken = new NoteToken(deployer);
        console.log("NoteToken:", address(noteToken));

        AutocallEngine engine = new AutocallEngine(
            deployer, USDC, address(hedgeManager), address(creConsumer),
            address(issuanceGate), address(couponCalculator),
            address(priceFeed), address(volOracle), address(carryEngine),
            address(noteToken)
        );
        console.log("AutocallEngine:", address(engine));

        XYieldVault vault = new XYieldVault(deployer, USDC, address(engine), address(noteToken));
        console.log("XYieldVault:", address(vault));

        ProtocolStats stats = new ProtocolStats(
            address(engine), address(vault), address(reserveFund), USDC
        );
        console.log("ProtocolStats:", address(stats));

        // ---- 6. Grant roles ----
        // AutocallEngine: vault + operator can create notes, deployer is keeper
        engine.grantRole(engine.VAULT_ROLE(), address(vault));
        engine.grantRole(engine.VAULT_ROLE(), deployer); // deployer acts as operator
        engine.grantRole(engine.KEEPER_ROLE(), deployer);

        // NoteToken: engine and vault can mint/burn
        noteToken.grantRole(noteToken.MINTER_ROLE(), address(engine));
        noteToken.grantRole(noteToken.MINTER_ROLE(), address(vault));
        noteToken.grantRole(noteToken.BURNER_ROLE(), address(engine));

        // XYieldVault: deployer is operator
        vault.grantRole(vault.OPERATOR_ROLE(), deployer);

        // VolOracle: deployer can update vols
        volOracle.grantRole(volOracle.UPDATER_ROLE(), deployer);

        // IssuanceGate: engine needs to call noteActivated/noteSettled
        issuanceGate.setAuthorized(address(engine), true);

        // HedgeManager: engine needs to call openHedge/closeHedge
        hedgeManager.setAuthorized(address(engine), true);

        // Transfer reserve ownership to epoch manager
        reserveFund.transferOwnership(address(epochManager));

        // Set fee collector on vault
        vault.setFeeCollector(address(feeCollector));

        vm.stopBroadcast();

        // ---- Summary ----
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("VolOracle:          ", address(volOracle));
        console.log("OptionPricer:       ", address(optionPricer));
        console.log("CREConsumer:        ", address(creConsumer));
        console.log("NadoAdapter:        ", address(nado));
        console.log("TydroAdapter:       ", address(tydro));
        console.log("OneInchSwapper:     ", address(swapper));
        console.log("PythAdapter:        ", address(priceFeed));
        console.log("HedgeManager:       ", address(hedgeManager));
        console.log("CarryEngine:        ", address(carryEngine));
        console.log("ReserveFund:        ", address(reserveFund));
        console.log("FeeCollector:       ", address(feeCollector));
        console.log("IssuanceGate:       ", address(issuanceGate));
        console.log("EpochManager:       ", address(epochManager));
        console.log("NoteToken:          ", address(noteToken));
        console.log("AutocallEngine:     ", address(engine));
        console.log("XYieldVault:        ", address(vault));
    }
}
