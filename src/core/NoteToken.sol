// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title NoteToken
/// @notice ERC-1155 soulbound token representing Phoenix Autocall note positions.
///         tokenId = uint256(noteId). Non-transferable in Phase 1.
contract NoteToken is ERC1155, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @dev noteId -> holder address (single holder per note in Phase 1)
    mapping(uint256 => address) public noteHolder;

    error TransferDisabled();
    error ZeroAddress();

    event NoteMinted(bytes32 indexed noteId, address indexed holder, uint256 amount);
    event NoteBurned(bytes32 indexed noteId, address indexed holder, uint256 amount);

    constructor(address admin) ERC1155("") {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Mint note tokens on claimDeposit
    /// @param to The holder address
    /// @param noteId The note identifier
    /// @param amount The notional amount (1 token = 1 USDC unit)
    function mint(address to, bytes32 noteId, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        uint256 tokenId = uint256(noteId);
        noteHolder[tokenId] = to;
        _mint(to, tokenId, amount, "");
        emit NoteMinted(noteId, to, amount);
    }

    /// @notice Burn note tokens on settlement
    /// @param from The holder address
    /// @param noteId The note identifier
    /// @param amount The amount to burn
    function burn(address from, bytes32 noteId, uint256 amount) external onlyRole(BURNER_ROLE) {
        uint256 tokenId = uint256(noteId);
        _burn(from, tokenId, amount);
        if (balanceOf(from, tokenId) == 0) {
            delete noteHolder[tokenId];
        }
        emit NoteBurned(noteId, from, amount);
    }

    /// @notice Returns the holder of a note
    function holderOf(bytes32 noteId) external view returns (address) {
        return noteHolder[uint256(noteId)];
    }

    // --- Soulbound: block all transfers in Phase 1 ---

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override
    {
        // Allow mints (from == 0) and burns (to == 0), block transfers
        if (from != address(0) && to != address(0)) {
            revert TransferDisabled();
        }
        super._update(from, to, ids, values);
    }

    // --- ERC165 ---

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
