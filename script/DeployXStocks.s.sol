// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mintable ERC20 xStock token for testnet
contract XStockToken is ERC20 {
    uint8 private _dec;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 initialSupply, address to)
        ERC20(name_, symbol_)
    {
        _dec = decimals_;
        _mint(to, initialSupply);
    }

    function decimals() public view override returns (uint8) { return _dec; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @title DeployXStocks
/// @notice Deploy all xStock tokens on Ink Sepolia for testing.
///         Mirrors the real xStocks catalog with 18 decimals and 1M supply each.
contract DeployXStocks is Script {

    struct TokenDef {
        string symbol;
        string name;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        uint256 supply = 1_000_000 ether; // 1M tokens each (18 decimals)

        console.log("Deployer:", deployer);

        // Define all xStock tokens
        TokenDef[30] memory tokens = [
            TokenDef("NVDAx",  "NVIDIA xStock"),
            TokenDef("TSLAx",  "Tesla xStock"),
            TokenDef("AAPLx",  "Apple xStock"),
            TokenDef("MSFTx",  "Microsoft xStock"),
            TokenDef("AMZNx",  "Amazon xStock"),
            TokenDef("GOOGLx", "Alphabet xStock"),
            TokenDef("METAx",  "Meta xStock"),
            TokenDef("AVGOx",  "Broadcom xStock"),
            TokenDef("AMDx",   "AMD xStock"),
            TokenDef("NFLXx",  "Netflix xStock"),
            TokenDef("JPMx",   "JPMorgan Chase xStock"),
            TokenDef("Vx",     "Visa xStock"),
            TokenDef("MAx",    "Mastercard xStock"),
            TokenDef("COINx",  "Coinbase xStock"),
            TokenDef("MSTRx",  "MicroStrategy xStock"),
            TokenDef("PLTRx",  "Palantir xStock"),
            TokenDef("CRMx",   "Salesforce xStock"),
            TokenDef("LLYx",   "Eli Lilly xStock"),
            TokenDef("ORCLx",  "Oracle xStock"),
            TokenDef("INTCx",  "Intel xStock"),
            TokenDef("GSx",    "Goldman Sachs xStock"),
            TokenDef("BACx",   "Bank of America xStock"),
            TokenDef("GLDx",   "Gold xStock"),
            TokenDef("SLVx",   "iShares Silver Trust xStock"),
            TokenDef("SPYx",   "SP500 xStock"),
            TokenDef("QQQx",   "Nasdaq xStock"),
            TokenDef("IWMx",   "Russell 2000 xStock"),
            TokenDef("TQQQx",  "TQQQ xStock"),
            TokenDef("HOODx",  "Robinhood xStock"),
            TokenDef("GMEx",   "Gamestop xStock")
        ];

        vm.startBroadcast(pk);

        for (uint256 i = 0; i < tokens.length; i++) {
            XStockToken token = new XStockToken(
                tokens[i].name,
                tokens[i].symbol,
                18,
                supply,
                deployer
            );
            console.log(tokens[i].symbol, ":", address(token));
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== ALL xSTOCK TOKENS DEPLOYED ===");
        console.log("Supply: 1,000,000 each (18 decimals)");
        console.log("Deployer holds all supply");
    }
}
