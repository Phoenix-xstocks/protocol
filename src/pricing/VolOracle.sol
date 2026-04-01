// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IVolOracle } from "../interfaces/IVolOracle.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/// @notice Chainlink CRE IReceiver interface.
interface IReceiver {
    function onReport(bytes calldata metadata, bytes calldata report) external;
}

/// @title VolOracle
/// @notice Stores implied volatilities and pairwise correlations for xStocks basket assets.
///         Updated by Chainlink CRE workflow ("xYield-VolOracle") via KeystoneForwarder,
///         or manually by UPDATER_ROLE. Falls back to admin-set vols when data is stale.
contract VolOracle is IVolOracle, IReceiver, ERC165, AccessControl {
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    /// @notice Address of the Chainlink KeystoneForwarder (validates DON signatures).
    address public forwarder;

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
    event ForwarderUpdated(address indexed newForwarder);

    constructor(address admin, address _forwarder) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        forwarder = _forwarder;
    }

    // ---------------------------------------------------------------
    // IReceiver implementation (called by KeystoneForwarder)
    // ---------------------------------------------------------------

    /// @notice Called by the CRE KeystoneForwarder after DON consensus.
    ///         report = abi.encode(address[] assets, uint256[] volsBps, uint256[] correlationsBps)
    function onReport(bytes calldata, bytes calldata report) external override {
        require(msg.sender == forwarder, "only forwarder");

        (address[] memory assets, uint256[] memory volsBps, uint256[] memory correlationsBps) =
            abi.decode(report, (address[], uint256[], uint256[]));

        _updateVols(assets, volsBps, correlationsBps);
    }

    // ---------------------------------------------------------------
    // ERC165
    // ---------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, AccessControl) returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || super.supportsInterface(interfaceId);
    }

    // ---------------------------------------------------------------
    // Manual update (UPDATER_ROLE — fallback if CRE is down)
    // ---------------------------------------------------------------

    function updateVols(
        address[] calldata assets,
        uint256[] calldata volsBps,
        uint256[] calldata correlationsBps
    ) external onlyRole(UPDATER_ROLE) {
        _updateVols(assets, volsBps, correlationsBps);
    }

    // ---------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------

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

    // ---------------------------------------------------------------
    // Admin configuration
    // ---------------------------------------------------------------

    function setForwarder(address _forwarder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_forwarder != address(0), "zero forwarder");
        forwarder = _forwarder;
        emit ForwarderUpdated(_forwarder);
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

    // ---------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------

    function _updateVols(
        address[] memory assets,
        uint256[] memory volsBps,
        uint256[] memory correlationsBps
    ) internal {
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

    function _pairKey(address a, address b) internal pure returns (bytes32 result) {
        (address lo, address hi) = a < b ? (a, b) : (b, a);
        assembly {
            mstore(0x00, shl(96, lo))
            mstore(0x14, shl(96, hi))
            result := keccak256(0x00, 40)
        }
    }

    function _isStale() internal view returns (bool) {
        return block.timestamp > lastUpdate + stalenessThreshold;
    }
}
