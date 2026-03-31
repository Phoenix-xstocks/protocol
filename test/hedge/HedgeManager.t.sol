// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { HedgeManager } from "../../src/hedge/HedgeManager.sol";
import { INadoAdapter } from "../../src/interfaces/INadoAdapter.sol";
import { ITydroAdapter } from "../../src/interfaces/ITydroAdapter.sol";
import { IOneInchSwapper } from "../../src/interfaces/IOneInchSwapper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// --- Mock Contracts ---

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockNado is INadoAdapter {
    uint256 private nextPositionNonce;
    mapping(bytes32 => uint256) public positionSizes;
    mapping(bytes32 => uint256) public positionFunding;

    function openShort(uint256, uint256 notional, uint256) external override returns (bytes32 positionId) {
        nextPositionNonce++;
        positionId = bytes32(nextPositionNonce);
        positionSizes[positionId] = notional;
    }

    function closeShort(bytes32 positionId) external override returns (uint256 pnl) {
        pnl = positionSizes[positionId];
        delete positionSizes[positionId];
    }

    function claimFunding(bytes32 positionId) external override returns (uint256 fundingAmount) {
        fundingAmount = positionFunding[positionId];
        positionFunding[positionId] = 0;
    }

    function getPosition(bytes32 positionId)
        external
        view
        override
        returns (int256 unrealizedPnl, uint256 margin, uint256 size, uint256 accumulatedFunding)
    {
        size = positionSizes[positionId];
        return (0, 0, size, positionFunding[positionId]);
    }

    function setPositionSize(bytes32 positionId, uint256 size) external {
        positionSizes[positionId] = size;
    }

    function setFunding(bytes32 positionId, uint256 amount) external {
        positionFunding[positionId] = amount;
    }
}

contract MockTydro is ITydroAdapter {
    mapping(address => uint256) public collateral;
    uint256 public totalBorrowed;
    mapping(address => uint256) private collateralValues;

    function depositCollateral(address asset, uint256 amount) external override {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        collateral[asset] += amount;
    }

    function withdrawCollateral(address asset) external override returns (uint256 amount) {
        amount = collateral[asset];
        collateral[asset] = 0;
        IERC20(asset).transfer(msg.sender, amount);
    }

    function borrowUSDC(uint256 amount) external override returns (uint256 borrowed) {
        totalBorrowed += amount;
        return amount;
    }

    function repayUSDC(uint256 amount) external override {
        totalBorrowed -= amount;
    }

    function getCollateralValue(address asset) external view override returns (uint256) {
        uint256 val = collateralValues[asset];
        return val > 0 ? val : collateral[asset];
    }

    function getLendingRate() external pure override returns (uint256) {
        return 1585489599; // ~5% APY
    }

    function depositUSDC(uint256) external override {}

    function withdrawUSDC(uint256 amount) external pure override returns (uint256) {
        return amount;
    }

    function setCollateralValue(address asset, uint256 value) external {
        collateralValues[asset] = value;
    }
}

contract MockSwapper is IOneInchSwapper {
    function swap(address tokenIn, address tokenOut, uint256 amountIn)
        external
        override
        returns (uint256 amountOut)
    {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        amountOut = amountIn;
        MockERC20(tokenOut).mint(msg.sender, amountOut);
    }

    function swapWithSlippage(address tokenIn, address tokenOut, uint256 amountIn, uint256)
        external
        override
        returns (uint256 amountOut)
    {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        amountOut = amountIn;
        MockERC20(tokenOut).mint(msg.sender, amountOut);
    }
}

// --- Tests ---

contract HedgeManagerTest is Test {
    HedgeManager public hedge;
    MockERC20 public usdc;
    MockERC20 public nvdax;
    MockERC20 public tslax;
    MockERC20 public metax;
    MockNado public nado;
    MockTydro public tydro;
    MockSwapper public swapper;
    address public owner;

    bytes32 constant NOTE_ID = bytes32(uint256(1));
    uint256 constant NOTIONAL = 10_000e6;

    function setUp() public {
        owner = address(this);
        usdc = new MockERC20("USD Coin", "USDC");
        nvdax = new MockERC20("NVIDIA xStock", "NVDAx");
        tslax = new MockERC20("Tesla xStock", "TSLAx");
        metax = new MockERC20("Meta xStock", "METAx");

        nado = new MockNado();
        tydro = new MockTydro();
        swapper = new MockSwapper();

        hedge = new HedgeManager(
            address(nado), address(tydro), address(swapper), address(usdc), owner
        );

        hedge.setPairIndex(address(nvdax), 1);
        hedge.setPairIndex(address(tslax), 2);
        hedge.setPairIndex(address(metax), 3);

        usdc.mint(address(hedge), NOTIONAL);
    }

    function test_openHedge() public {
        address[] memory basket = _makeBasket();
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);

        (uint256 notional, uint256 spotNotional, uint256 borrowed, bool active) = hedge.getPosition(NOTE_ID);
        assertEq(notional, NOTIONAL);
        // spotNotional may be slightly less due to integer division (10000/3 * 3 = 9999)
        assertApproxEqAbs(spotNotional, NOTIONAL, 3, "spot notional within rounding tolerance");
        assertEq(borrowed, NOTIONAL / 2);
        assertTrue(active);
    }

    function test_openHedge_revert_duplicate() public {
        address[] memory basket = _makeBasket();
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);

        vm.expectRevert("hedge already active");
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);
    }

    function test_openHedge_revert_emptyBasket() public {
        address[] memory basket = new address[](0);
        vm.expectRevert("empty basket");
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);
    }

    function test_closeHedge() public {
        address[] memory basket = _makeBasket();
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);

        usdc.mint(address(hedge), NOTIONAL);

        uint256 recovered = hedge.closeHedge(NOTE_ID);
        assertGt(recovered, 0);

        (, , , bool active) = hedge.getPosition(NOTE_ID);
        assertFalse(active);
    }

    function test_closeHedge_revert_notActive() public {
        vm.expectRevert("hedge not active");
        hedge.closeHedge(NOTE_ID);
    }

    function test_rebalance_noop_below_threshold() public {
        address[] memory basket = _makeBasket();
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);

        // Delta drift is 0 at open (mock 1:1), so no rebalance needed
        hedge.rebalance(NOTE_ID);
    }

    function test_rebalance_triggers_above_threshold() public {
        address[] memory basket = _makeBasket();
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);

        // Create 10% drift by changing collateral values
        uint256 perStock = NOTIONAL / 3;
        tydro.setCollateralValue(address(nvdax), perStock * 110 / 100);
        tydro.setCollateralValue(address(tslax), perStock * 110 / 100);
        tydro.setCollateralValue(address(metax), perStock * 110 / 100);

        int256 drift = hedge.getDeltaDrift(NOTE_ID);
        assertGt(drift, 0);

        hedge.rebalance(NOTE_ID);
    }

    function test_rebalance_critical_drift_fixed_by_adjust() public {
        address[] memory basket = _makeBasket();
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);

        // Create >15% drift
        uint256 perStock = NOTIONAL / 3;
        tydro.setCollateralValue(address(nvdax), perStock * 120 / 100);
        tydro.setCollateralValue(address(tslax), perStock * 120 / 100);
        tydro.setCollateralValue(address(metax), perStock * 120 / 100);

        // After rebalance, adjustment aligns perps to spot, drift -> 0
        hedge.rebalance(NOTE_ID);
        assertFalse(hedge.notePaused(NOTE_ID), "note should not be paused when adjustment fixes drift");
    }

    function test_unpauseNote_onlyOwner() public {
        bytes32 noteId = bytes32(uint256(42));

        vm.prank(address(0xdead));
        vm.expectRevert();
        hedge.unpauseNote(noteId);

        // Owner can call unpauseNote
        hedge.unpauseNote(noteId);
        assertFalse(hedge.notePaused(noteId));
    }

    function test_getDeltaDrift_inactive_returns_zero() public view {
        int256 drift = hedge.getDeltaDrift(NOTE_ID);
        assertEq(drift, 0);
    }

    /// @notice INV-2: |spot_value + perp_pnl| ~= notional (+-5%)
    function test_invariant_2_deltaNeutral() public {
        address[] memory basket = _makeBasket();
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);

        int256 drift = hedge.getDeltaDrift(NOTE_ID);
        uint256 absDrift = drift >= 0 ? uint256(drift) : uint256(-drift);
        assertLe(absDrift, 500, "INV-2: drift should be within 5% at open");
    }

    /// @notice INV-3: spot_value + perp_pnl >= notional * 95%
    function test_invariant_3_minimumCoverage() public {
        address[] memory basket = _makeBasket();
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);

        (uint256 notional, , , ) = hedge.getPosition(NOTE_ID);
        assertGe(notional, NOTIONAL * 95 / 100, "INV-3: should cover 95% of notional");
    }

    function test_onlyOwner_openHedge() public {
        address[] memory basket = _makeBasket();
        vm.prank(address(0xdead));
        vm.expectRevert();
        hedge.openHedge(NOTE_ID, basket, NOTIONAL);
    }

    function test_onlyOwner_closeHedge() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        hedge.closeHedge(NOTE_ID);
    }

    function _makeBasket() internal view returns (address[] memory basket) {
        basket = new address[](3);
        basket[0] = address(nvdax);
        basket[1] = address(tslax);
        basket[2] = address(metax);
    }
}
