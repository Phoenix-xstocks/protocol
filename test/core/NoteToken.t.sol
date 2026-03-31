// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { NoteToken } from "../../src/core/NoteToken.sol";

contract NoteTokenTest is Test {
    NoteToken public token;

    address admin = address(this);
    address minter = address(0x1111);
    address burner = address(0x2222);
    address holder = address(0x3333);
    address other = address(0x4444);

    bytes32 noteId = keccak256("note-1");
    uint256 tokenId;

    function setUp() public {
        token = new NoteToken(admin);
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.BURNER_ROLE(), burner);
        tokenId = uint256(noteId);
    }

    // --- Mint tests ---

    function test_mint_success() public {
        vm.prank(minter);
        token.mint(holder, noteId, 1000e6);

        assertEq(token.balanceOf(holder, tokenId), 1000e6);
        assertEq(token.holderOf(noteId), holder);
    }

    function test_mint_emits_event() public {
        vm.expectEmit(true, true, false, true);
        emit NoteToken.NoteMinted(noteId, holder, 1000e6);

        vm.prank(minter);
        token.mint(holder, noteId, 1000e6);
    }

    function test_mint_reverts_without_role() public {
        vm.prank(other);
        vm.expectRevert();
        token.mint(holder, noteId, 1000e6);
    }

    function test_mint_reverts_zero_address() public {
        vm.prank(minter);
        vm.expectRevert(NoteToken.ZeroAddress.selector);
        token.mint(address(0), noteId, 1000e6);
    }

    // --- Burn tests ---

    function test_burn_success() public {
        vm.prank(minter);
        token.mint(holder, noteId, 1000e6);

        vm.prank(burner);
        token.burn(holder, noteId, 1000e6);

        assertEq(token.balanceOf(holder, tokenId), 0);
        assertEq(token.holderOf(noteId), address(0));
    }

    function test_burn_partial() public {
        vm.prank(minter);
        token.mint(holder, noteId, 1000e6);

        vm.prank(burner);
        token.burn(holder, noteId, 400e6);

        assertEq(token.balanceOf(holder, tokenId), 600e6);
        assertEq(token.holderOf(noteId), holder);
    }

    function test_burn_reverts_without_role() public {
        vm.prank(minter);
        token.mint(holder, noteId, 1000e6);

        vm.prank(other);
        vm.expectRevert();
        token.burn(holder, noteId, 1000e6);
    }

    // --- Soulbound (non-transferable) tests ---

    function test_transfer_reverts() public {
        vm.prank(minter);
        token.mint(holder, noteId, 1000e6);

        vm.prank(holder);
        vm.expectRevert(NoteToken.TransferDisabled.selector);
        token.safeTransferFrom(holder, other, tokenId, 500e6, "");
    }

    function test_batch_transfer_reverts() public {
        vm.prank(minter);
        token.mint(holder, noteId, 1000e6);

        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500e6;

        vm.prank(holder);
        vm.expectRevert(NoteToken.TransferDisabled.selector);
        token.safeBatchTransferFrom(holder, other, ids, amounts, "");
    }

    // --- Constructor ---

    function test_constructor_reverts_zero_admin() public {
        vm.expectRevert(NoteToken.ZeroAddress.selector);
        new NoteToken(address(0));
    }

    // --- supportsInterface ---

    function test_supports_erc1155_interface() public view {
        // ERC-1155 interfaceId = 0xd9b67a26
        assertTrue(token.supportsInterface(0xd9b67a26));
    }

    function test_supports_access_control_interface() public view {
        // AccessControl interfaceId
        assertTrue(token.supportsInterface(type(IAccessControlInterface).interfaceId));
    }
}

// Minimal interface to get the AccessControl interfaceId for the test
interface IAccessControlInterface {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;
}
