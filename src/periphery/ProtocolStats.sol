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
    IAutocallEngine public immutable ENGINE;
    IXYieldVault public immutable VAULT;
    IReserveFund public immutable RESERVE_FUND;
    IERC20 public immutable USDC;

    constructor(
        address _engine,
        address _vault,
        address _reserveFund,
        address _usdc
    ) {
        ENGINE = IAutocallEngine(_engine);
        VAULT = IXYieldVault(_vault);
        RESERVE_FUND = IReserveFund(_reserveFund);
        USDC = IERC20(_usdc);
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
        stats.totalNotesCreated = ENGINE.getNoteCount();
        stats.tvl = VAULT.totalAssets();
        stats.maxDeposit = VAULT.maxDeposit(address(0));
        stats.reserveBalance = RESERVE_FUND.getBalance();
        stats.engineUsdcBalance = USDC.balanceOf(address(ENGINE));
        stats.vaultUsdcBalance = USDC.balanceOf(address(VAULT));
        stats.reserveLevel = totalNotional > 0
            ? RESERVE_FUND.getLevel(totalNotional)
            : 10000;
    }
}
