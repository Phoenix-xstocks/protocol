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
import { IOneInchSwapper } from "../src/interfaces/IOneInchSwapper.sol";
import { PythAdapter } from "../src/integrations/PythAdapter.sol";
import { CouponStreamer } from "../src/integrations/SablierStream.sol";

// Periphery
import { ReserveFund } from "../src/periphery/ReserveFund.sol";
import { EpochManager } from "../src/periphery/EpochManager.sol";
import { ProtocolStats } from "../src/periphery/ProtocolStats.sol";
import { FeeCollector } from "../src/periphery/FeeCollector.sol";

/// @title Deploy
/// @notice Full protocol deployment to Ink Sepolia testnet.
///         Real addresses: Tydro xStocks pool, Chainlink CRE forwarder, Pyth.
///         Mock/skip: Nado perps (not on Ink), 1inch (using TestnetSwap).
contract Deploy is Script {
    // Ink Sepolia testnet token addresses
    address constant USDC = 0x6b57475467cd854d36Be7FB614caDa5207838943;
    address constant WQQQX = 0x267ED9BC43B16D832cB9Aaf0e3445f0cC9f536d9;
    address constant WSPYX = 0x9eF9f9B22d3CA9769e28e769e2AAA3C2B0072D0e;

    // External protocols
    address constant MOCK_NADO_PERP = address(0x1001); // Nado not on Ink testnet — skipped via testnetMode
    address constant TYDRO_POOL = 0x6807dc923806fE8Fd134338EABCA509979a7e0cB; // Tydro Ink Sepolia xStocks
    address constant TESTNET_SWAP = 0x10415db61BC994f00028B6Cc1bddc04c76bd0fB4; // TestnetSwap on Ink Sepolia
    address constant PYTH = 0x2880aB155794e7179c9eE2e38200202908C17B43; // Pyth on Ink Sepolia
    // Chainlink CRE KeystoneForwarder on Ink Sepolia (production)
    address constant CRE_FORWARDER = 0x76c9cf548b4179F8901cda1f8623568b58215E62;
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address treasury = deployer; // treasury = deployer for testnet

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPk);

        // ---- 1. Pricing layer (no protocol deps) ----
        VolOracle volOracle = new VolOracle(deployer, CRE_FORWARDER);
        console.log("VolOracle:", address(volOracle));

        OptionPricer optionPricer = new OptionPricer(address(volOracle), deployer);
        console.log("OptionPricer:", address(optionPricer));

        CREConsumer creConsumer = new CREConsumer(CRE_FORWARDER, address(optionPricer), deployer);
        console.log("CREConsumer:", address(creConsumer));

        CouponCalculator couponCalculator = new CouponCalculator();
        console.log("CouponCalculator:", address(couponCalculator));

        // ---- 2. Integration adapters ----
        NadoAdapter nado = new NadoAdapter(MOCK_NADO_PERP, USDC, deployer);
        console.log("NadoAdapter:", address(nado));

        TydroAdapter tydro = new TydroAdapter(TYDRO_POOL, USDC, deployer);
        console.log("TydroAdapter:", address(tydro));

        // Use TestnetSwap directly (implements IOneInchSwapper)
        IOneInchSwapper swapper = IOneInchSwapper(TESTNET_SWAP);
        console.log("Swapper (TestnetSwap):", address(swapper));

        PythAdapter priceFeed = new PythAdapter(PYTH, deployer);
        console.log("PythAdapter:", address(priceFeed));

        // Coupon streaming (self-contained linear vesting, no external Sablier needed)
        CouponStreamer couponStreamer = new CouponStreamer(USDC, deployer);
        console.log("CouponStreamer:", address(couponStreamer));

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

        // CREConsumer: engine needs to call registerNoteParams
        creConsumer.setAutocallEngine(address(engine));

        // IssuanceGate: engine needs to call noteActivated/noteSettled
        issuanceGate.setAuthorized(address(engine), true);

        // HedgeManager: engine needs to call openHedge/closeHedge
        hedgeManager.setAuthorized(address(engine), true);
        hedgeManager.setTestnetMode(true); // skip Nado perps only (Tydro collateral is live)
        engine.setTestnetMode(true); // skip CRE check in issuance gate

        // Transfer adapter ownership to HedgeManager (it calls them directly)
        tydro.transferOwnership(address(hedgeManager));
        nado.transferOwnership(address(hedgeManager));

        // Transfer reserve ownership to epoch manager
        reserveFund.transferOwnership(address(epochManager));

        // Set fee collector on vault
        vault.setFeeCollector(address(feeCollector));

        // Wire coupon streaming into AutocallEngine and transfer ownership
        engine.setSablierStream(address(couponStreamer));
        couponStreamer.transferOwnership(address(engine));

        // ---- 7. Configure Pyth feed IDs for official xStock tokens ----
        // WSPYX → SPYX/USD
        bytes32 spyxFeed = 0x2817b78438c769357182c04346fddaad1178c82f4048828fe0997c3c64624e14;
        // WQQQX → QQQX/USD
        bytes32 qqqxFeed = 0x178a6f73a5aede9d0d682e86b0047c9f333ed0efe5c6537ca937565219c4054d;

        engine.setFeedId(WSPYX, spyxFeed);
        engine.setFeedId(WQQQX, qqqxFeed);
        priceFeed.setFeedId(WSPYX, spyxFeed);
        priceFeed.setFeedId(WQQQX, qqqxFeed);

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
        console.log("CouponStreamer:      ", address(couponStreamer));
        console.log("NoteToken:          ", address(noteToken));
        console.log("AutocallEngine:     ", address(engine));
        console.log("XYieldVault:        ", address(vault));
    }
}
