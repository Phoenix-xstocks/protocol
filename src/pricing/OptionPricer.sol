// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOptionPricer, PricingParams } from "../interfaces/IOptionPricer.sol";
import { IVolOracle } from "../interfaces/IVolOracle.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title OptionPricer
/// @notice Analytical worst-of put approximation for on-chain verification.
///         Serves as a bound check -- rejects MC results that diverge too much.
contract OptionPricer is IOptionPricer, Ownable {
    uint256 public constant BPS = 10000;

    uint256 public constant TOLERANCE_HIGH_VOL = 300;
    uint256 public constant TOLERANCE_MID_VOL = 200;
    uint256 public constant TOLERANCE_LOW_VOL = 150;

    uint256 public constant MIN_PREMIUM = 300;
    uint256 public constant MAX_PREMIUM = 1500;
    uint256 public constant MAX_KI_PROB = 1500;

    IVolOracle public volOracle;

    event VolOracleUpdated(address indexed newOracle);

    constructor(address _volOracle, address _owner) Ownable(_owner) {
        require(_volOracle != address(0), "zero address");
        volOracle = IVolOracle(_volOracle);
    }

    function verifyPricing(
        PricingParams calldata params,
        uint256 mcPremiumBps,
        bytes32 /* mcHash */
    ) external view returns (bool approved, uint256 onChainApprox) {
        require(params.basket.length >= 2, "need >= 2 assets");

        uint256 avgVol = _getAvgVol(params.basket);
        uint256 avgCorr = volOracle.getAvgCorrelation(params.basket);
        uint256 T = (params.maturityDays * 1e18) / 365;

        uint256 singlePut = _bsApproxPut(avgVol, params.kiBarrierBps, T);
        uint256 worstOfMult = _sqrt(params.basket.length * 1e18);
        uint256 corrAdj = 1e18 - (avgCorr * 1e18 / (2 * BPS));

        onChainApprox = (singlePut * worstOfMult * corrAdj) / (1e9 * 1e18);
        onChainApprox = (onChainApprox * BPS * 365) / (params.maturityDays * 1e18);

        uint256 tolerance = _getTolerance(avgVol);

        uint256 diff = mcPremiumBps > onChainApprox
            ? mcPremiumBps - onChainApprox
            : onChainApprox - mcPremiumBps;

        approved = diff <= tolerance && mcPremiumBps >= MIN_PREMIUM && mcPremiumBps <= MAX_PREMIUM;
    }

    function setVolOracle(address _volOracle) external onlyOwner {
        require(_volOracle != address(0), "zero address");
        volOracle = IVolOracle(_volOracle);
        emit VolOracleUpdated(_volOracle);
    }

    function _getAvgVol(address[] calldata basket) internal view returns (uint256) {
        uint256 total;
        for (uint256 i = 0; i < basket.length; i++) {
            total += volOracle.getVol(basket[i]);
        }
        return total / basket.length;
    }

    function _getTolerance(uint256 avgVol) internal pure returns (uint256) {
        if (avgVol >= 5000) return TOLERANCE_HIGH_VOL;
        if (avgVol >= 3500) return TOLERANCE_MID_VOL;
        return TOLERANCE_LOW_VOL;
    }

    function _bsApproxPut(uint256 volBps, uint256 kiBarrierBps, uint256 T) internal pure returns (uint256) {
        uint256 vol = (volBps * 1e18) / BPS;
        uint256 sqrtT = _sqrt(T);
        uint256 volSqrtT = (vol * sqrtT) / 1e9;

        uint256 barrierRatio = (kiBarrierBps * 1e18) / BPS;
        uint256 oneE18 = 1e18;
        uint256 logApprox;
        if (barrierRatio < oneE18) {
            logApprox = (2 * (oneE18 - barrierRatio) * oneE18) / (oneE18 + barrierRatio);
        }

        if (volSqrtT == 0) return 0;

        uint256 otmDiscount;
        uint256 scaledLog = (logApprox * 4) / 10;
        if (volSqrtT > scaledLog) {
            otmDiscount = volSqrtT - scaledLog;
        } else {
            otmDiscount = (volSqrtT * 15) / 100;
        }

        uint256 putValue = (barrierRatio * otmDiscount) / oneE18;
        return putValue;
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = x;
        uint256 y = (z + 1) / 2;
        while (y < z) {
            z = y;
            y = (z + x / z) / 2;
        }
        return z;
    }
}
