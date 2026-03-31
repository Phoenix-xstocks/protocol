// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { NadoAdapter, INadoPerp } from "../../src/integrations/NadoAdapter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockNadoPerp {
    mapping(bytes32 => bool) public positions;
    uint256 private _nextId;

    function openPosition(uint256, bool, uint256, uint256, address)
        external
        returns (bytes32 positionId)
    {
        positionId = keccak256(abi.encodePacked(_nextId++));
        positions[positionId] = true;
    }

    function closePosition(bytes32 positionId) external returns (int256 pnl) {
        require(positions[positionId], "no position");
        positions[positionId] = false;
        pnl = 500e6; // mock positive PnL
    }

    function claimFunding(bytes32) external pure returns (uint256 fundingAmount) {
        fundingAmount = 100e6;
    }

    function getPosition(bytes32)
        external
        pure
        returns (int256 unrealizedPnl, uint256 margin, uint256 size, uint256 accumulatedFunding)
    {
        return (200e6, 1000e6, 3000e6, 50e6);
    }
}

contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract NadoAdapterTest is Test {
    NadoAdapter public adapter;
    MockNadoPerp public mockPerp;
    MockERC20 public mockToken;
    address public owner = address(this);

    function setUp() public {
        mockPerp = new MockNadoPerp();
        mockToken = new MockERC20();
        adapter = new NadoAdapter(address(mockPerp), address(mockToken), owner);

        // Fund the adapter with margin tokens
        mockToken.mint(address(adapter), 100_000e6);
    }

    function test_openShort() public {
        bytes32 positionId = adapter.openShort(1, 10_000e6, 2);
        assertTrue(positionId != bytes32(0), "position ID should be non-zero");

        (,,, bool open) = adapter.positions(positionId);
        assertTrue(open, "position should be open");
    }

    function test_closeShort() public {
        bytes32 positionId = adapter.openShort(1, 10_000e6, 2);
        uint256 pnl = adapter.closeShort(positionId);
        assertEq(pnl, 500e6, "PnL should match mock return");

        (,,, bool open) = adapter.positions(positionId);
        assertFalse(open, "position should be closed");
    }

    function test_closeShort_reverts_if_not_open() public {
        bytes32 fakeId = keccak256("fake");
        vm.expectRevert(abi.encodeWithSelector(NadoAdapter.PositionNotOpen.selector, fakeId));
        adapter.closeShort(fakeId);
    }

    function test_claimFunding() public {
        bytes32 positionId = adapter.openShort(1, 10_000e6, 2);
        uint256 funding = adapter.claimFunding(positionId);
        assertEq(funding, 100e6, "funding should match mock return");
    }

    function test_claimFunding_reverts_if_not_open() public {
        bytes32 fakeId = keccak256("fake");
        vm.expectRevert(abi.encodeWithSelector(NadoAdapter.PositionNotOpen.selector, fakeId));
        adapter.claimFunding(fakeId);
    }

    function test_getPosition() public {
        bytes32 positionId = adapter.openShort(1, 10_000e6, 2);
        (int256 pnl, uint256 margin, uint256 size, uint256 funding) = adapter.getPosition(positionId);
        assertEq(pnl, 200e6);
        assertEq(margin, 1000e6);
        assertEq(size, 3000e6);
        assertEq(funding, 50e6);
    }

    function test_onlyOwner_openShort() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        adapter.openShort(1, 10_000e6, 2);
    }

    function test_onlyOwner_closeShort() public {
        bytes32 positionId = adapter.openShort(1, 10_000e6, 2);
        vm.prank(address(0xdead));
        vm.expectRevert();
        adapter.closeShort(positionId);
    }

    function test_recoverToken() public {
        MockERC20 stray = new MockERC20();
        stray.mint(address(adapter), 1000e6);
        adapter.recoverToken(address(stray), 1000e6);
        assertEq(stray.balanceOf(owner), 1000e6);
    }
}
