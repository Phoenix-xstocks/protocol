// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IssuanceGate } from "../../src/pricing/IssuanceGate.sol";
import { ICREConsumer, PricingResult } from "../../src/interfaces/ICREConsumer.sol";
import { IHedgeManager } from "../../src/interfaces/IHedgeManager.sol";
import { IReserveFund } from "../../src/interfaces/IReserveFund.sol";

contract MockCREConsumer is ICREConsumer {
    mapping(bytes32 => PricingResult) public results;
    mapping(bytes32 => bool) public accepted;

    function setPricing(bytes32 noteId, PricingResult calldata result) external {
        results[noteId] = result;
        accepted[noteId] = true;
    }

    function fulfillPricing(bytes32, PricingResult calldata) external pure {}

    function getAcceptedPricing(bytes32 noteId) external view returns (PricingResult memory) {
        require(accepted[noteId], "pricing not accepted");
        return results[noteId];
    }
}

contract MockHedgeManager is IHedgeManager {
    int256 public drift = 0;
    function openHedge(bytes32, address[] calldata, uint256) external {}
    function closeHedge(bytes32) external returns (uint256) { return 0; }
    function rebalance(bytes32) external {}
    function getDeltaDrift(bytes32) external view returns (int256) { return drift; }
    function setDrift(int256 _drift) external { drift = _drift; }
}

contract MockReserveFund is IReserveFund {
    uint256 public level = 500;
    function deposit(uint256) external {}
    function coverDeficit(uint256) external returns (uint256) { return 0; }
    function getBalance() external pure returns (uint256) { return 1e6; }
    function getLevel(uint256) external view returns (uint256) { return level; }
    function getHaircutRatio(uint256) external pure returns (uint256) { return 10000; }
    function setLevel(uint256 _level) external { level = _level; }
}

contract IssuanceGateTest is Test {
    IssuanceGate public gate;
    MockCREConsumer public mockCRE;
    MockHedgeManager public mockHedge;
    MockReserveFund public mockReserve;

    address owner = address(this);
    bytes32 noteId = keccak256("note-1");

    address constant NVDA = address(0x1);
    address constant TSLA = address(0x2);
    address constant META = address(0x3);

    function setUp() public {
        mockCRE = new MockCREConsumer();
        mockHedge = new MockHedgeManager();
        mockReserve = new MockReserveFund();
        gate = new IssuanceGate(address(mockCRE), address(mockHedge), address(mockReserve), owner);

        PricingResult memory result = PricingResult({
            putPremiumBps: 920,
            kiProbabilityBps: 800,
            expectedKILossBps: 400,
            vegaBps: 150,
            inputsHash: bytes32(0)
        });
        mockCRE.setPricing(noteId, result);
    }

    function _defaultBasket() internal pure returns (address[] memory) {
        address[] memory basket = new address[](3);
        basket[0] = NVDA;
        basket[1] = TSLA;
        basket[2] = META;
        return basket;
    }

    function test_checkIssuance_approved() public view {
        (bool approved, string memory reason) = gate.checkIssuance(noteId, 10_000e6, _defaultBasket());
        assertTrue(approved, "should be approved");
        assertEq(bytes(reason).length, 0, "no reason on approval");
    }

    function test_rejectNoPricing() public view {
        bytes32 unknownNote = keccak256("unknown");
        (bool approved, string memory reason) = gate.checkIssuance(unknownNote, 10_000e6, _defaultBasket());
        assertFalse(approved);
        assertEq(reason, "pricing not accepted");
    }

    function test_rejectLowReserve() public {
        mockReserve.setLevel(200);
        (bool approved, string memory reason) = gate.checkIssuance(noteId, 10_000e6, _defaultBasket());
        assertFalse(approved);
        assertEq(reason, "reserve below minimum");
    }

    function test_rejectMaxActiveNotes() public {
        for (uint256 i = 0; i < 500; i++) {
            gate.noteActivated(100e6);
        }
        (bool approved, string memory reason) = gate.checkIssuance(noteId, 10_000e6, _defaultBasket());
        assertFalse(approved);
        assertEq(reason, "max active notes reached");
    }

    function test_rejectNotionalTooSmall() public view {
        (bool approved, string memory reason) = gate.checkIssuance(noteId, 50e6, _defaultBasket());
        assertFalse(approved);
        assertEq(reason, "notional below minimum");
    }

    function test_rejectNotionalTooLarge() public view {
        (bool approved, string memory reason) = gate.checkIssuance(noteId, 200_000e6, _defaultBasket());
        assertFalse(approved);
        assertEq(reason, "notional above maximum");
    }

    function test_noteActivatedAndSettled() public {
        gate.noteActivated(10_000e6);
        assertEq(gate.activeNoteCount(), 1);
        assertEq(gate.totalNotionalOutstanding(), 10_000e6);
        gate.noteSettled(10_000e6);
        assertEq(gate.activeNoteCount(), 0);
        assertEq(gate.totalNotionalOutstanding(), 0);
    }

    function test_noteSettled_revertNoActiveNotes() public {
        vm.expectRevert("no active notes");
        gate.noteSettled(10_000e6);
    }

    function test_noteActivated_onlyOwner() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        gate.noteActivated(10_000e6);
    }

    function test_exactMinNotional() public view {
        (bool approved,) = gate.checkIssuance(noteId, 100e6, _defaultBasket());
        assertTrue(approved);
    }

    function test_exactMaxNotional() public view {
        (bool approved,) = gate.checkIssuance(noteId, 100_000e6, _defaultBasket());
        assertTrue(approved);
    }

    function test_reserveAtExactMinimum() public {
        mockReserve.setLevel(300);
        (bool approved,) = gate.checkIssuance(noteId, 10_000e6, _defaultBasket());
        assertTrue(approved, "should pass at exact minimum reserve");
    }

    function test_rejectTVLCapExceeded() public {
        // Activate notes worth 4.95M, then try to add 100k (total > 5M)
        gate.noteActivated(4_950_000e6);
        (bool approved, string memory reason) = gate.checkIssuance(noteId, 100_000e6, _defaultBasket());
        assertFalse(approved);
        assertEq(reason, "TVL cap exceeded");
    }

    function test_constants() public view {
        assertEq(gate.MAX_ACTIVE_NOTES(), 500);
        assertEq(gate.MIN_NOTE_SIZE(), 100e6);
        assertEq(gate.MAX_NOTE_SIZE(), 100_000e6);
        assertEq(gate.RESERVE_MINIMUM_BPS(), 300);
        assertEq(gate.MAX_TVL(), 5_000_000e6);
    }

    function test_setDependencies() public {
        MockCREConsumer newCRE = new MockCREConsumer();
        gate.setDependencies(address(newCRE), address(0), address(0));
        assertEq(address(gate.creConsumer()), address(newCRE));
    }
}
