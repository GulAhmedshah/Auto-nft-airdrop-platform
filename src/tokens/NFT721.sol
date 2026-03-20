// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721A} from "@erc721a/contracts/ERC721A.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title  NFT721
 * @author NFT Airdrop Platform — P1-I2
 * @notice Gas-optimised ERC-721 NFT contract built on ERC721A with role-based
 *         access control, pausability, configurable max supply, and IPFS metadata.
 *
 * Roles
 * ─────
 *   DEFAULT_ADMIN_ROLE  – can grant/revoke roles, set base URI, pause/unpause
 *   MINTER_ROLE         – can call mint()
 *   AIRDROP_ROLE        – can call batchMint()
 */
contract NFT721 is ERC721A, AccessControl, Pausable {
    using Strings for uint256;

    // ──────────────────────────────────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────────────────────────────────

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");

    // ──────────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Maximum number of tokens that can ever be minted.
    ///         0 = unlimited supply.
    uint256 public immutable maxSupply;

    /// @dev Base URI used for tokenURI construction (e.g. "ipfs://Qm.../")
    string private _baseTokenURI;

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Emitted after every successful mint (single or batch).
     * @param to       Recipient address.
     * @param tokenId  First token ID in the minted range.
     * @param quantity Number of tokens minted in this call.
     */
    event NFTMinted(address indexed to, uint256 tokenId, uint256 quantity);

    /**
     * @notice Emitted when the base URI is updated.
     * @param newBaseURI The new base URI string.
     */
    event BaseURIUpdated(string newBaseURI);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    /// @dev Thrown when minting would exceed maxSupply (when maxSupply > 0).
    error ExceedsMaxSupply(uint256 requested, uint256 available);

    /// @dev Thrown when batchMint arrays have mismatched lengths.
    error ArrayLengthMismatch(uint256 recipientsLen, uint256 quantitiesLen);

    /// @dev Thrown when a zero-quantity mint is attempted.
    error ZeroQuantity();

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @param name_      ERC-721 token name (e.g. "My NFT Collection").
     * @param symbol_    ERC-721 token symbol (e.g. "MNC").
     * @param baseURI_   Initial base URI (e.g. "ipfs://Qm.../"). Must end with '/'.
     * @param maxSupply_ Hard cap on total minted supply. Pass 0 for unlimited.
     * @param admin_     Address that receives DEFAULT_ADMIN_ROLE on deployment.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint256 maxSupply_,
        address admin_
    ) ERC721A(name_, symbol_) {
        require(admin_ != address(0), "NFT721: zero admin address");

        maxSupply = maxSupply_;
        _baseTokenURI = baseURI_;

        // Grant the deployer-nominated admin all three roles so the contract is
        // immediately operational without a second transaction.
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
        _grantRole(AIRDROP_ROLE, admin_);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Minting
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Mint `quantity` consecutive tokens to `to`.
     * @dev    Restricted to MINTER_ROLE. Respects pause and maxSupply.
     * @param to       Recipient address.
     * @param quantity Number of tokens to mint (must be > 0).
     */
    function mint(
        address to,
        uint256 quantity
    ) external whenNotPaused onlyRole(MINTER_ROLE) {
        if (quantity == 0) revert ZeroQuantity();
        _enforceCap(quantity);

        uint256 firstTokenId = _nextTokenId();
        _mint(to, quantity);

        emit NFTMinted(to, firstTokenId, quantity);
    }

    /**
     * @notice Mint tokens in bulk to multiple recipients in a single transaction.
     * @dev    Restricted to AIRDROP_ROLE. `recipients` and `quantities` must have
     *         the same length. Respects pause and maxSupply (total across all
     *         recipients in this call).
     * @param recipients  Array of recipient addresses.
     * @param quantities  Corresponding quantities for each recipient.
     */
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata quantities
    ) external whenNotPaused onlyRole(AIRDROP_ROLE) {
        uint256 len = recipients.length;
        if (len != quantities.length) {
            revert ArrayLengthMismatch(len, quantities.length);
        }

        // Pre-compute total so we make ONE cap check (cheaper than N checks).
        uint256 total;
        for (uint256 i; i < len; ) {
            if (quantities[i] == 0) revert ZeroQuantity();
            total += quantities[i];
            unchecked {
                ++i;
            }
        }
        _enforceCap(total);

        for (uint256 i; i < len; ) {
            uint256 firstTokenId = _nextTokenId();
            _mint(recipients[i], quantities[i]);
            emit NFTMinted(recipients[i], firstTokenId, quantities[i]);
            unchecked {
                ++i;
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Metadata
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns the metadata URI for `tokenId`.
     *         Format: baseURI + tokenId + ".json"
     *         Example: "ipfs://Qm.../42.json"
     * @param tokenId The token whose URI to return.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        return
            string(
                abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json")
            );
    }

    /**
     * @notice Update the base URI for all tokens.
     * @dev    Restricted to DEFAULT_ADMIN_ROLE.
     * @param newBaseURI New base URI string (should end with '/').
     */
    function setBaseURI(
        string memory newBaseURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Pause
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Pause all minting operations.
     * @dev    Restricted to DEFAULT_ADMIN_ROLE.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Resume minting operations.
     * @dev    Restricted to DEFAULT_ADMIN_ROLE.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Views
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns the current base URI.
     */
    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice Returns remaining mintable supply.
     *         Returns type(uint256).max when maxSupply == 0 (unlimited).
     */
    function remainingSupply() external view returns (uint256) {
        if (maxSupply == 0) return type(uint256).max;
        uint256 minted = _totalMinted();
        return maxSupply > minted ? maxSupply - minted : 0;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ──────────────────────────────────────────────────────────────────────────

    /// @dev Reverts if minting `quantity` more tokens would exceed maxSupply.
    ///      When maxSupply == 0 the check is skipped entirely.
    function _enforceCap(uint256 quantity) internal view {
        if (maxSupply == 0) return;
        uint256 minted = _totalMinted();
        if (minted + quantity > maxSupply) {
            revert ExceedsMaxSupply(quantity, maxSupply - minted);
        }
    }

    /// @dev ERC721A starts token IDs at 1 (more gas-friendly for most use cases).
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // ERC-165 supportsInterface override (required by both ERC721A + AccessControl)
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @inheritdoc ERC721A
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721A, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
