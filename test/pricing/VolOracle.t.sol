// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { VolOracle } from "../../src/pricing/VolOracle.sol";

contract VolOracleTest is Test {
    VolOracle public oracle;

    address owner = address(this);
    address updater = address(0xBEEF);
    address nonUpdater = address(0xDEAD);

    address constant NVDA = address(0x1);
    address constant TSLA = address(0x2);
    address constant META = address(0x3);
    address constant AAPL = address(0x4);

    function setUp() public {
        oracle = new VolOracle(owner, address(0xF0F0));
        oracle.grantRole(oracle.UPDATER_ROLE(), updater);
    }

    // ---------------------------------------------------------------
    // Helper to build a standard 3-asset update
    // ---------------------------------------------------------------
    function _buildUpdate3()
        internal
        pure
        returns (address[] memory assets, uint256[] memory vols, uint256[] memory corrs)
    {
        assets = new address[](3);
        assets[0] = NVDA;
        assets[1] = TSLA;
        assets[2] = META;

        vols = new uint256[](3);
        vols[0] = 5500; // 55%
        vols[1] = 6000; // 60%
        vols[2] = 4000; // 40%

        // 3 assets -> 3 correlations: (0,1), (0,2), (1,2)
        corrs = new uint256[](3);
        corrs[0] = 5500;
        corrs[1] = 4800;
        corrs[2] = 5200;
    }

    function _doUpdate3() internal {
        (address[] memory assets, uint256[] memory vols, uint256[] memory corrs) = _buildUpdate3();
        vm.prank(updater);
        oracle.updateVols(assets, vols, corrs);
    }

    // ---------------------------------------------------------------
    // updateVols: correct storage
    // ---------------------------------------------------------------
    function test_updateVols_storesVolsCorrectly() public {
        _doUpdate3();

        assertEq(oracle.vols(NVDA), 5500);
        assertEq(oracle.vols(TSLA), 6000);
        assertEq(oracle.vols(META), 4000);
    }

    function test_updateVols_storesCorrelationsCorrectly() public {
        _doUpdate3();

        // Verify by calling getAvgCorrelation with 2-asset pairs
        address[] memory pair = new address[](2);

        pair[0] = NVDA;
        pair[1] = TSLA;
        assertEq(oracle.getAvgCorrelation(pair), 5500, "NVDA-TSLA corr");

        pair[0] = NVDA;
        pair[1] = META;
        assertEq(oracle.getAvgCorrelation(pair), 4800, "NVDA-META corr");

        pair[0] = TSLA;
        pair[1] = META;
        assertEq(oracle.getAvgCorrelation(pair), 5200, "TSLA-META corr");
    }

    function test_updateVols_updatesLastUpdate() public {
        uint256 ts = 1700000000;
        vm.warp(ts);
        _doUpdate3();
        assertEq(oracle.getLastUpdate(), ts);
    }

    function test_updateVols_tracksAssets() public {
        _doUpdate3();

        assertTrue(oracle.isTracked(NVDA));
        assertTrue(oracle.isTracked(TSLA));
        assertTrue(oracle.isTracked(META));
        assertFalse(oracle.isTracked(AAPL));
    }

    function test_updateVols_doesNotDuplicateTrackedAssets() public {
        _doUpdate3();
        // Update again with the same assets
        _doUpdate3();

        assertEq(oracle.trackedAssets(0), NVDA);
        assertEq(oracle.trackedAssets(1), TSLA);
        assertEq(oracle.trackedAssets(2), META);

        // Accessing index 3 should revert (no 4th element)
        vm.expectRevert();
        oracle.trackedAssets(3);
    }

    // ---------------------------------------------------------------
    // updateVols: emits event
    // ---------------------------------------------------------------
    function test_updateVols_emitsEvent() public {
        (address[] memory assets, uint256[] memory vols, uint256[] memory corrs) = _buildUpdate3();

        vm.prank(updater);
        vm.expectEmit(false, false, false, true);
        emit VolOracle.VolsUpdated(assets, vols, corrs, block.timestamp);
        oracle.updateVols(assets, vols, corrs);
    }

    // ---------------------------------------------------------------
    // updateVols: UPDATER_ROLE required
    // ---------------------------------------------------------------
    function test_updateVols_revertsWithoutUpdaterRole() public {
        (address[] memory assets, uint256[] memory vols, uint256[] memory corrs) = _buildUpdate3();

        vm.prank(nonUpdater);
        vm.expectRevert();
        oracle.updateVols(assets, vols, corrs);
    }

    function test_updateVols_revertsFromOwnerWithoutRole() public {
        (address[] memory assets, uint256[] memory vols, uint256[] memory corrs) = _buildUpdate3();

        // Owner does not have UPDATER_ROLE by default
        vm.expectRevert();
        oracle.updateVols(assets, vols, corrs);
    }

    // ---------------------------------------------------------------
    // updateVols: validation
    // ---------------------------------------------------------------
    function test_updateVols_revertsOnSingleAsset() public {
        address[] memory assets = new address[](1);
        assets[0] = NVDA;
        uint256[] memory vols = new uint256[](1);
        vols[0] = 5000;
        uint256[] memory corrs = new uint256[](0);

        vm.prank(updater);
        vm.expectRevert("need >= 2 assets");
        oracle.updateVols(assets, vols, corrs);
    }

    function test_updateVols_revertsOnLengthMismatch() public {
        address[] memory assets = new address[](2);
        assets[0] = NVDA;
        assets[1] = TSLA;
        uint256[] memory vols = new uint256[](3); // wrong length
        uint256[] memory corrs = new uint256[](1);

        vm.prank(updater);
        vm.expectRevert("length mismatch");
        oracle.updateVols(assets, vols, corrs);
    }

    function test_updateVols_revertsOnCorrLengthMismatch() public {
        address[] memory assets = new address[](2);
        assets[0] = NVDA;
        assets[1] = TSLA;
        uint256[] memory vols = new uint256[](2);
        vols[0] = 5000;
        vols[1] = 4000;
        uint256[] memory corrs = new uint256[](2); // should be 1

        vm.prank(updater);
        vm.expectRevert("corr length mismatch");
        oracle.updateVols(assets, vols, corrs);
    }

    function test_updateVols_revertsOnZeroVol() public {
        address[] memory assets = new address[](2);
        assets[0] = NVDA;
        assets[1] = TSLA;
        uint256[] memory vols = new uint256[](2);
        vols[0] = 0; // zero vol
        vols[1] = 4000;
        uint256[] memory corrs = new uint256[](1);
        corrs[0] = 5000;

        vm.prank(updater);
        vm.expectRevert("vol out of range");
        oracle.updateVols(assets, vols, corrs);
    }

    function test_updateVols_revertsOnVolAbove200pct() public {
        address[] memory assets = new address[](2);
        assets[0] = NVDA;
        assets[1] = TSLA;
        uint256[] memory vols = new uint256[](2);
        vols[0] = 20001; // > 200%
        vols[1] = 4000;
        uint256[] memory corrs = new uint256[](1);
        corrs[0] = 5000;

        vm.prank(updater);
        vm.expectRevert("vol out of range");
        oracle.updateVols(assets, vols, corrs);
    }

    function test_updateVols_revertsOnCorrAbove100pct() public {
        address[] memory assets = new address[](2);
        assets[0] = NVDA;
        assets[1] = TSLA;
        uint256[] memory vols = new uint256[](2);
        vols[0] = 5000;
        vols[1] = 4000;
        uint256[] memory corrs = new uint256[](1);
        corrs[0] = 10001; // > 100%

        vm.prank(updater);
        vm.expectRevert("corr out of range");
        oracle.updateVols(assets, vols, corrs);
    }

    // ---------------------------------------------------------------
    // getVol: returns correct vol
    // ---------------------------------------------------------------
    function test_getVol_returnsCorrectVol() public {
        _doUpdate3();
        assertEq(oracle.getVol(NVDA), 5500);
        assertEq(oracle.getVol(TSLA), 6000);
        assertEq(oracle.getVol(META), 4000);
    }

    // ---------------------------------------------------------------
    // getVol: fallback when stale
    // ---------------------------------------------------------------
    function test_getVol_fallsBackWhenStale() public {
        _doUpdate3();

        // Set a fallback vol for NVDA
        oracle.setFallbackVol(NVDA, 7000);

        // Advance time past staleness threshold (2 hours)
        vm.warp(block.timestamp + 2 hours + 1);

        assertEq(oracle.getVol(NVDA), 7000, "should return fallback vol when stale");
    }

    function test_getVol_revertsWhenNoData() public {
        // No vol data set at all for AAPL
        vm.expectRevert("no vol data");
        oracle.getVol(AAPL);
    }

    function test_getVol_revertsWhenStaleAndNoFallback() public {
        _doUpdate3();

        // Advance time past staleness threshold, NVDA has no fallback
        vm.warp(block.timestamp + 2 hours + 1);

        vm.expectRevert("no vol data");
        oracle.getVol(NVDA);
    }

    // ---------------------------------------------------------------
    // getAvgCorrelation: correct average
    // ---------------------------------------------------------------
    function test_getAvgCorrelation_correctAverage() public {
        _doUpdate3();

        address[] memory basket = new address[](3);
        basket[0] = NVDA;
        basket[1] = TSLA;
        basket[2] = META;

        // Average of (5500, 4800, 5200) = 15500 / 3 = 5166
        uint256 avg = oracle.getAvgCorrelation(basket);
        assertEq(avg, 5166);
    }

    function test_getAvgCorrelation_twoAssets() public {
        _doUpdate3();

        address[] memory pair = new address[](2);
        pair[0] = NVDA;
        pair[1] = TSLA;

        assertEq(oracle.getAvgCorrelation(pair), 5500);
    }

    // ---------------------------------------------------------------
    // getAvgCorrelation: fallback when stale
    // ---------------------------------------------------------------
    function test_getAvgCorrelation_fallbackWhenStale() public {
        _doUpdate3();

        // Set fallback correlations
        oracle.setFallbackCorrelation(NVDA, TSLA, 8000);

        // Make data stale
        vm.warp(block.timestamp + 2 hours + 1);

        address[] memory pair = new address[](2);
        pair[0] = NVDA;
        pair[1] = TSLA;

        assertEq(oracle.getAvgCorrelation(pair), 8000, "should use fallback when stale");
    }

    function test_getAvgCorrelation_revertsOnSingleAsset() public {
        address[] memory single = new address[](1);
        single[0] = NVDA;

        vm.expectRevert("need >= 2 assets");
        oracle.getAvgCorrelation(single);
    }

    // ---------------------------------------------------------------
    // Staleness: isStale after 2h, not before
    // ---------------------------------------------------------------
    function test_staleness_notStaleBeforeThreshold() public {
        uint256 startTs = 1700000000;
        vm.warp(startTs);
        _doUpdate3();

        // Still within 2 hours
        vm.warp(startTs + 2 hours);
        assertEq(oracle.getVol(NVDA), 5500, "not stale at exactly 2h");
    }

    function test_staleness_staleAfterThreshold() public {
        uint256 startTs = 1700000000;
        vm.warp(startTs);
        _doUpdate3();

        oracle.setFallbackVol(NVDA, 7777);

        // 1 second past threshold
        vm.warp(startTs + 2 hours + 1);
        assertEq(oracle.getVol(NVDA), 7777, "stale after 2h + 1s");
    }

    function test_staleness_notStaleAfterFreshUpdate() public {
        uint256 startTs = 1700000000;
        vm.warp(startTs);
        _doUpdate3();

        // Advance past staleness
        vm.warp(startTs + 3 hours);

        // Do a fresh update
        _doUpdate3();

        // Data should be fresh now
        assertEq(oracle.getVol(NVDA), 5500, "fresh after re-update");
    }

    function test_setStalenessThreshold() public {
        oracle.setStalenessThreshold(4 hours);
        assertEq(oracle.stalenessThreshold(), 4 hours);
    }

    function test_setStalenessThreshold_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit VolOracle.StalenessThresholdUpdated(4 hours);
        oracle.setStalenessThreshold(4 hours);
    }

    function test_setStalenessThreshold_revertsOnTooLow() public {
        vm.expectRevert("threshold out of range");
        oracle.setStalenessThreshold(30 minutes);
    }

    function test_setStalenessThreshold_revertsOnTooHigh() public {
        vm.expectRevert("threshold out of range");
        oracle.setStalenessThreshold(49 hours);
    }

    function test_setStalenessThreshold_onlyAdmin() public {
        vm.prank(nonUpdater);
        vm.expectRevert();
        oracle.setStalenessThreshold(4 hours);
    }

    // ---------------------------------------------------------------
    // Multiple assets tracked
    // ---------------------------------------------------------------
    function test_multipleAssets_fourAssets() public {
        address[] memory assets = new address[](4);
        assets[0] = NVDA;
        assets[1] = TSLA;
        assets[2] = META;
        assets[3] = AAPL;

        uint256[] memory vols = new uint256[](4);
        vols[0] = 5500;
        vols[1] = 6000;
        vols[2] = 4000;
        vols[3] = 3500;

        // 4 assets -> 6 correlations: (0,1),(0,2),(0,3),(1,2),(1,3),(2,3)
        uint256[] memory corrs = new uint256[](6);
        corrs[0] = 5500;
        corrs[1] = 4800;
        corrs[2] = 5000;
        corrs[3] = 5200;
        corrs[4] = 4500;
        corrs[5] = 4700;

        vm.prank(updater);
        oracle.updateVols(assets, vols, corrs);

        assertEq(oracle.vols(NVDA), 5500);
        assertEq(oracle.vols(TSLA), 6000);
        assertEq(oracle.vols(META), 4000);
        assertEq(oracle.vols(AAPL), 3500);

        assertTrue(oracle.isTracked(NVDA));
        assertTrue(oracle.isTracked(TSLA));
        assertTrue(oracle.isTracked(META));
        assertTrue(oracle.isTracked(AAPL));

        // Average of all 6 correlations:
        // (5500+4800+5000+5200+4500+4700) / 6 = 29700 / 6 = 4950
        address[] memory basket = new address[](4);
        basket[0] = NVDA;
        basket[1] = TSLA;
        basket[2] = META;
        basket[3] = AAPL;
        assertEq(oracle.getAvgCorrelation(basket), 4950);
    }

    // ---------------------------------------------------------------
    // setFallbackVol
    // ---------------------------------------------------------------
    function test_setFallbackVol_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit VolOracle.FallbackVolSet(NVDA, 6000);
        oracle.setFallbackVol(NVDA, 6000);
    }

    function test_setFallbackVol_revertsOnZero() public {
        vm.expectRevert("vol out of range");
        oracle.setFallbackVol(NVDA, 0);
    }

    function test_setFallbackVol_revertsAboveMax() public {
        vm.expectRevert("vol out of range");
        oracle.setFallbackVol(NVDA, 20001);
    }

    function test_setFallbackVol_onlyAdmin() public {
        vm.prank(nonUpdater);
        vm.expectRevert();
        oracle.setFallbackVol(NVDA, 5000);
    }

    // ---------------------------------------------------------------
    // setFallbackCorrelation
    // ---------------------------------------------------------------
    function test_setFallbackCorrelation_revertsAboveMax() public {
        vm.expectRevert("corr out of range");
        oracle.setFallbackCorrelation(NVDA, TSLA, 10001);
    }

    function test_setFallbackCorrelation_onlyAdmin() public {
        vm.prank(nonUpdater);
        vm.expectRevert();
        oracle.setFallbackCorrelation(NVDA, TSLA, 5000);
    }

    // ---------------------------------------------------------------
    // Edge: boundary vol values (1 and 20000)
    // ---------------------------------------------------------------
    function test_updateVols_boundaryValues() public {
        address[] memory assets = new address[](2);
        assets[0] = NVDA;
        assets[1] = TSLA;

        uint256[] memory vols = new uint256[](2);
        vols[0] = 1;     // minimum valid
        vols[1] = 20000; // maximum valid (200%)

        uint256[] memory corrs = new uint256[](1);
        corrs[0] = 10000; // 100% correlation

        vm.prank(updater);
        oracle.updateVols(assets, vols, corrs);

        assertEq(oracle.vols(NVDA), 1);
        assertEq(oracle.vols(TSLA), 20000);
    }

    // ---------------------------------------------------------------
    // Pair key symmetry: order of assets should not matter
    // ---------------------------------------------------------------
    function test_getAvgCorrelation_pairKeySymmetry() public {
        _doUpdate3();

        address[] memory pairAB = new address[](2);
        pairAB[0] = NVDA;
        pairAB[1] = TSLA;

        address[] memory pairBA = new address[](2);
        pairBA[0] = TSLA;
        pairBA[1] = NVDA;

        assertEq(
            oracle.getAvgCorrelation(pairAB),
            oracle.getAvgCorrelation(pairBA),
            "pair key should be symmetric"
        );
    }
}
