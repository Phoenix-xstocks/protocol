// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IAutocallEngine } from "../interfaces/IAutocallEngine.sol";
import { IReserveFund } from "../interfaces/IReserveFund.sol";
import { IXYieldVault } from "../interfaces/IXYieldVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ProtocolStats
/// @notice Read-only aggregator for protocol-wide dashboard metrics.
///         All view functions — no state changes, no gas cost.
contract ProtocolStats {
    IAutocallEngine public immutable engine;
    IXYieldVault public immutable vault;
    IReserveFund public immutable reserveFund;
    IERC20 public immutable usdc;

    constructor(
        address _engine,
        address _vault,
        address _reserveFund,
        address _usdc
    ) {
        engine = IAutocallEngine(_engine);
        vault = IXYieldVault(_vault);
        reserveFund = IReserveFund(_reserveFund);
        usdc = IERC20(_usdc);
    }

    struct Stats {
        uint256 totalNotesCreated;
        uint256 tvl;
        uint256 maxDeposit;
        uint256 reserveBalance;       // total including Euler yield
        uint256 engineUsdcBalance;
        uint256 vaultUsdcBalance;
        uint256 reserveLevel;         // bps of TVL
    }

    /// @notice Get all protocol stats in a single call
    function getStats(uint256 totalNotional) external view returns (Stats memory stats) {
        stats.totalNotesCreated = engine.getNoteCount();
        stats.tvl = vault.totalAssets();
        stats.maxDeposit = vault.maxDeposit(address(0));
        stats.reserveBalance = reserveFund.getBalance();
        stats.engineUsdcBalance = usdc.balanceOf(address(engine));
        stats.vaultUsdcBalance = usdc.balanceOf(address(vault));
        stats.reserveLevel = totalNotional > 0
            ? reserveFund.getLevel(totalNotional)
            : 10000;
    }
}
