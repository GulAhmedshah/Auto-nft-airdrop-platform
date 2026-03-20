// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title  NFT1155
 * @author NFT Airdrop Platform — P1-I3
 * @notice Semi-fungible / edition-based NFT contract built on OZ ERC1155.
 *         Supports per-token-ID supply caps, batch minting, bulk airdrop,
 *         per-ID custom URIs with base URI fallback, and burn functions.
 *
 * ── Roles ───────────────────────────────────────────────────────────────────
 *   DEFAULT_ADMIN_ROLE  – grant/revoke roles, set URIs, pause/unpause,
 *                         configure per-id max supply
 *   MINTER_ROLE         – call mint() and mintBatch()
 *   AIRDROP_ROLE        – call airdropBatch()
 *
 * ── Key difference from ERC-721 ─────────────────────────────────────────────
 *   ERC-1155 tokens are identified by (id, amount) pairs.
 *   Token ID 1 can have 10,000 copies — each copy is NOT unique.
 *   Think: "Edition 1 of artwork X" where 10,000 editions exist.
 */
contract NFT1155 is ERC1155, AccessControl, Pausable {
    using Strings for uint256;

    // ─────────────────────────────────────────────────────────────────────────
    // Roles
    // ─────────────────────────────────────────────────────────────────────────

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Human-readable name of the collection (not part of ERC-1155 standard).
    string public name;

    /// @notice Human-readable symbol of the collection.
    string public symbol;

    /// @notice Base URI used as fallback when no per-id URI is set.
    ///         Format expected: "ipfs://Qm.../" — tokenId + ".json" appended at runtime.
    string private _baseTokenURI;

    /// @notice Per-token-ID maximum supply. 0 = unlimited for that id.
    mapping(uint256 => uint256) public maxSupply;

    /// @notice Per-token-ID total minted so far.
    mapping(uint256 => uint256) public totalMinted;

    /// @notice Per-token-ID custom URI override. Empty = use base URI fallback.
    mapping(uint256 => string) private _tokenURIs;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Emitted after every successful mint operation.
     * @param to     Recipient address.
     * @param id     Token ID minted.
     * @param amount Quantity minted.
     */
    event TokenMinted(address indexed to, uint256 indexed id, uint256 amount);

    /**
     * @notice Emitted when a per-id max supply is configured.
     * @param id        Token ID.
     * @param maxAmount Maximum supply for this id (0 = unlimited).
     */
    event MaxSupplySet(uint256 indexed id, uint256 maxAmount);

    /**
     * @notice Emitted when the base URI is updated.
     */
    event BaseURIUpdated(string newBaseURI);

    /**
     * @notice Emitted when a per-id URI override is set.
     */
    event TokenURISet(uint256 indexed id, string tokenURI);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Minting would exceed the per-id max supply.
    error ExceedsMaxSupply(uint256 id, uint256 requested, uint256 available);

    /// @dev Arrays passed to a batch function have different lengths.
    error ArrayLengthMismatch(uint256 len1, uint256 len2);

    /// @dev A zero-amount mint was attempted.
    error ZeroAmount();

    /// @dev Caller is not the token owner or approved operator (for burns).
    error NotOwnerOrApproved();

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param name_      Collection name (e.g. "Airdrop Badges").
     * @param symbol_    Collection symbol (e.g. "BADGE").
     * @param baseURI_   Initial base URI (e.g. "ipfs://Qm.../").
     * @param admin_     Address granted DEFAULT_ADMIN_ROLE on deployment.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address admin_
    )
        ERC1155(baseURI_) // OZ ERC1155 stores its own URI too; we manage ours separately
    {
        require(admin_ != address(0), "NFT1155: zero admin address");

        name = name_;
        symbol = symbol_;
        _baseTokenURI = baseURI_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
        _grantRole(AIRDROP_ROLE, admin_);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin: supply caps & URIs
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Configure the maximum supply for a specific token ID.
     * @dev    Must be called BEFORE minting begins for that id, or set to a
     *         value >= totalMinted[id]. Pass 0 for unlimited.
     * @param id        Token ID to configure.
     * @param maxAmount Hard cap on total minted for this id.
     */
    function setMaxSupply(
        uint256 id,
        uint256 maxAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            maxAmount == 0 || maxAmount >= totalMinted[id],
            "NFT1155: cap below already-minted amount"
        );
        maxSupply[id] = maxAmount;
        emit MaxSupplySet(id, maxAmount);
    }

    /**
     * @notice Set a per-id URI override.
     *         If set, uri(id) returns this value instead of the base URI fallback.
     * @param id       Token ID.
     * @param tokenURI Full URI string (e.g. "ipfs://QmSpecific/metadata.json").
     */
    function setURI(
        uint256 id,
        string memory tokenURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _tokenURIs[id] = tokenURI;
        emit TokenURISet(id, tokenURI);
    }

    /**
     * @notice Update the base URI fallback for all token IDs.
     * @param newBaseURI New base URI (should end with '/').
     */
    function setBaseURI(
        string memory newBaseURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Minting
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Mint `amount` copies of token `id` to `to`.
     * @dev    Restricted to MINTER_ROLE. Respects pause and per-id maxSupply.
     * @param to     Recipient address.
     * @param id     Token ID to mint.
     * @param amount Number of copies to mint.
     * @param data   Optional calldata forwarded to recipient if it's a contract.
     */
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external whenNotPaused onlyRole(MINTER_ROLE) {
        if (amount == 0) revert ZeroAmount();
        _enforceCapSingle(id, amount);

        totalMinted[id] += amount;
        _mint(to, id, amount, data);

        emit TokenMinted(to, id, amount);
    }

    /**
     * @notice Mint multiple token IDs to a single address in one transaction.
     * @dev    Restricted to MINTER_ROLE. Each id is cap-checked individually.
     * @param to      Recipient address.
     * @param ids     Array of token IDs.
     * @param amounts Corresponding amounts for each id.
     * @param data    Optional calldata.
     */
    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external whenNotPaused onlyRole(MINTER_ROLE) {
        uint256 len = ids.length;
        if (len != amounts.length)
            revert ArrayLengthMismatch(len, amounts.length);

        // Pre-validate all caps before touching state
        for (uint256 i; i < len; ) {
            if (amounts[i] == 0) revert ZeroAmount();
            _enforceCapSingle(ids[i], amounts[i]);
            unchecked {
                ++i;
            }
        }

        // Update totalMinted for each id
        for (uint256 i; i < len; ) {
            totalMinted[ids[i]] += amounts[i];
            emit TokenMinted(to, ids[i], amounts[i]);
            unchecked {
                ++i;
            }
        }

        _mintBatch(to, ids, amounts, data);
    }

    /**
     * @notice Airdrop the same token ID to many recipients in one transaction.
     * @dev    Restricted to AIRDROP_ROLE.
     *         Total minted = recipients.length * amountEach — checked against cap upfront.
     * @param recipients  Array of recipient addresses.
     * @param id          Token ID to distribute.
     * @param amountEach  Amount each recipient receives.
     */
    function airdropBatch(
        address[] calldata recipients,
        uint256 id,
        uint256 amountEach
    ) external whenNotPaused onlyRole(AIRDROP_ROLE) {
        uint256 len = recipients.length;
        if (len == 0) revert ZeroAmount();
        if (amountEach == 0) revert ZeroAmount();

        // Pre-compute total and enforce cap once
        uint256 totalAmount = len * amountEach;
        _enforceCapSingle(id, totalAmount);

        // Update totalMinted once (not inside loop — one SSTORE)
        totalMinted[id] += totalAmount;

        for (uint256 i; i < len; ) {
            _mint(recipients[i], id, amountEach, "");
            emit TokenMinted(recipients[i], id, amountEach);
            unchecked {
                ++i;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Burn
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Burn `value` copies of token `id` from `account`.
     * @dev    Caller must be `account` or an approved operator for `account`.
     * @param account Address whose tokens are burned.
     * @param id      Token ID to burn.
     * @param value   Quantity to burn.
     */
    function burn(address account, uint256 id, uint256 value) external {
        _requireOwnerOrApproved(account);
        _burn(account, id, value);
    }

    /**
     * @notice Burn multiple token IDs from `account` in one transaction.
     * @dev    Caller must be `account` or an approved operator for `account`.
     * @param account Address whose tokens are burned.
     * @param ids     Array of token IDs to burn.
     * @param values  Corresponding amounts to burn for each id.
     */
    function burnBatch(
        address account,
        uint256[] calldata ids,
        uint256[] calldata values
    ) external {
        if (ids.length != values.length) {
            revert ArrayLengthMismatch(ids.length, values.length);
        }
        _requireOwnerOrApproved(account);
        _burnBatch(account, ids, values);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pause
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Pause all minting and transfers.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Resume minting and transfers.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // URI logic
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns the metadata URI for token `id`.
     *
     *         Priority:
     *           1. Per-id override (_tokenURIs[id]) if set
     *           2. baseURI + id + ".json" fallback
     *
     * @param id Token ID whose URI to return.
     */
    function uri(uint256 id) public view override returns (string memory) {
        string memory custom = _tokenURIs[id];
        if (bytes(custom).length > 0) {
            return custom;
        }
        return string(abi.encodePacked(_baseTokenURI, id.toString(), ".json"));
    }

    /**
     * @notice Returns the current base URI.
     */
    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice Returns remaining mintable supply for a specific token id.
     *         Returns type(uint256).max when maxSupply[id] == 0 (unlimited).
     */
    function remainingSupply(uint256 id) external view returns (uint256) {
        uint256 cap = maxSupply[id];
        if (cap == 0) return type(uint256).max;
        uint256 minted = totalMinted[id];
        return cap > minted ? cap - minted : 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Transfer hooks — enforce pause on transfers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev OZ ERC1155 calls _update for every mint, burn, and transfer.
     *      We hook it here to block all token movements when paused.
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override whenNotPaused {
        super._update(from, to, ids, values);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Reverts if minting `amount` of `id` would exceed maxSupply[id].
    ///      Skipped when maxSupply[id] == 0 (unlimited).
    function _enforceCapSingle(uint256 id, uint256 amount) internal view {
        uint256 cap = maxSupply[id];
        if (cap == 0) return;
        uint256 minted = totalMinted[id];
        if (minted + amount > cap) {
            revert ExceedsMaxSupply(id, amount, cap - minted);
        }
    }

    /// @dev Reverts if `msg.sender` is not `account` and not approved for `account`.
    function _requireOwnerOrApproved(address account) internal view {
        if (account != msg.sender && !isApprovedForAll(account, msg.sender)) {
            revert NotOwnerOrApproved();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ERC-165
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @inheritdoc ERC1155
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
