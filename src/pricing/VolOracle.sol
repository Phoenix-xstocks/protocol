// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IVolOracle } from "../interfaces/IVolOracle.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title VolOracle
/// @notice Stores implied volatilities and pairwise correlations for xStocks basket assets.
///         Updated by Chainlink CRE workflow ("xYield-VolOracle"), with fallback to realized vol.
contract VolOracle is IVolOracle, AccessControl {
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    mapping(address => uint256) public vols;
    mapping(bytes32 => uint256) public correlations;
    address[] public trackedAssets;
    mapping(address => bool) public isTracked;
    uint256 public lastUpdate;
    uint256 public stalenessThreshold = 2 hours;
    mapping(address => uint256) public fallbackVols;
    mapping(bytes32 => uint256) public fallbackCorrelations;

    event VolsUpdated(address[] assets, uint256[] volsBps, uint256[] correlationsBps, uint256 timestamp);
    event FallbackVolSet(address asset, uint256 volBps);
    event StalenessThresholdUpdated(uint256 newThreshold);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function updateVols(
        address[] calldata assets,
        uint256[] calldata volsBps,
        uint256[] calldata correlationsBps
    ) external onlyRole(UPDATER_ROLE) {
        require(assets.length >= 2, "need >= 2 assets");
        require(assets.length == volsBps.length, "length mismatch");
        uint256 expectedCorrs = (assets.length * (assets.length - 1)) / 2;
        require(correlationsBps.length == expectedCorrs, "corr length mismatch");

        for (uint256 i = 0; i < assets.length; i++) {
            require(volsBps[i] > 0 && volsBps[i] <= 20000, "vol out of range");
            vols[assets[i]] = volsBps[i];
            if (!isTracked[assets[i]]) {
                trackedAssets.push(assets[i]);
                isTracked[assets[i]] = true;
            }
        }

        uint256 corrIdx = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            for (uint256 j = i + 1; j < assets.length; j++) {
                bytes32 pairKey = _pairKey(assets[i], assets[j]);
                require(correlationsBps[corrIdx] <= 10000, "corr out of range");
                correlations[pairKey] = correlationsBps[corrIdx];
                corrIdx++;
            }
        }

        lastUpdate = block.timestamp;
        emit VolsUpdated(assets, volsBps, correlationsBps, block.timestamp);
    }

    function getVol(address asset) external view returns (uint256 volBps) {
        volBps = vols[asset];
        if (volBps == 0 || _isStale()) {
            volBps = fallbackVols[asset];
        }
        require(volBps > 0, "no vol data");
    }

    function getAvgCorrelation(address[] calldata basket) external view returns (uint256 avgCorrBps) {
        require(basket.length >= 2, "need >= 2 assets");
        uint256 totalCorr;
        uint256 count;
        for (uint256 i = 0; i < basket.length; i++) {
            for (uint256 j = i + 1; j < basket.length; j++) {
                bytes32 pairKey = _pairKey(basket[i], basket[j]);
                uint256 corr = correlations[pairKey];
                if (corr == 0 || _isStale()) {
                    corr = fallbackCorrelations[pairKey];
                }
                totalCorr += corr;
                count++;
            }
        }
        avgCorrBps = count > 0 ? totalCorr / count : 0;
    }

    function getLastUpdate() external view returns (uint256 timestamp) {
        return lastUpdate;
    }

    function setFallbackVol(address asset, uint256 volBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(volBps > 0 && volBps <= 20000, "vol out of range");
        fallbackVols[asset] = volBps;
        emit FallbackVolSet(asset, volBps);
    }

    function setFallbackCorrelation(address asset1, address asset2, uint256 corrBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(corrBps <= 10000, "corr out of range");
        fallbackCorrelations[_pairKey(asset1, asset2)] = corrBps;
    }

    function setStalenessThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newThreshold >= 1 hours && newThreshold <= 48 hours, "threshold out of range");
        stalenessThreshold = newThreshold;
        emit StalenessThresholdUpdated(newThreshold);
    }

    function _pairKey(address a, address b) internal pure returns (bytes32) {
        (address lo, address hi) = a < b ? (a, b) : (b, a);
        return keccak256(abi.encodePacked(lo, hi));
    }

    function _isStale() internal view returns (bool) {
        return block.timestamp > lastUpdate + stalenessThreshold;
    }
}
