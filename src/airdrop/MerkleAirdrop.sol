// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl}    from "@openzeppelin/contracts/access/AccessControl.sol";
import {MerkleProof}      from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BitMaps}          from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {INFT721}          from "../tokens/INFT721.sol";
import {INFT1155}         from "../tokens/INFT1155.sol";

/**
 * @title  MerkleAirdrop
 * @author NFT Airdrop Platform — P1-I5
 * @notice Gas-efficient, allowlist-based airdrop using Merkle proofs.
 *         Recipients self-claim by submitting a proof that their entry
 *         is included in the published Merkle tree.
 *
 * ── How It Works (plain English) ────────────────────────────────────────────
 *
 *  OFF-CHAIN (admin work before deploy):
 *   1. Build a list of (index, address, amount) entries — the "whitelist".
 *   2. Hash every entry into a leaf:
 *        leaf = keccak256(abi.encodePacked(index, account, amount))
 *   3. Arrange leaves into a binary Merkle tree.
 *   4. The tree root is a single bytes32 that "fingerprints" the whole list.
 *   5. For each recipient, pre-compute a proof (an array of sibling hashes).
 *
 *  ON-CHAIN (contract side):
 *   • Admin stores just the 32-byte root — costs almost nothing.
 *   • When Alice claims, she submits her (index, amount, proof).
 *   • The contract re-hashes her leaf and walks up the tree using the proof.
 *   • If the final hash matches the stored root → she's on the list → mint.
 *   • A bitmap records index as claimed → second claim reverts.
 *
 * ── Token Type Support ───────────────────────────────────────────────────────
 *   ERC-721:  amount = quantity of tokens to mint
 *   ERC-1155: amount = copies of tokenId to mint (tokenId set at deploy)
 *
 * ── Bitmap vs Boolean Mapping ────────────────────────────────────────────────
 *   A boolean mapping uses one full 32-byte storage slot per index.
 *   A bitmap packs 256 booleans into one 32-byte slot.
 *   For 10,000 claimers: bitmap = ~40 slots vs mapping = ~10,000 slots.
 *   Savings: ~250x fewer storage writes → massive gas reduction.
 */
contract MerkleAirdrop is AccessControl {
    using BitMaps   for BitMaps.BitMap;
    using MerkleProof for bytes32[];

    // ─────────────────────────────────────────────────────────────────────────
    // Token type enum
    // ─────────────────────────────────────────────────────────────────────────

    enum TokenType { ERC721, ERC1155 }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice The Merkle root that defines the full eligibility list.
    ///         Admin updates this to issue a new airdrop round.
    bytes32 public merkleRoot;

    /// @notice Address of the NFT contract that will mint tokens to claimers.
    address public immutable tokenContract;

    /// @notice Type of the token contract (ERC721 or ERC1155).
    TokenType public immutable tokenType;

    /// @notice For ERC-1155 claims: which token ID to mint.
    ///         Ignored for ERC-721 claims.
    uint256 public immutable tokenId;

    /// @notice Whether claiming is currently open.
    ///         Admin can toggle this to pause/resume the claim window.
    bool public claimOpen;

    /// @notice Bitmap tracking which indexes have already been claimed.
    ///         Packs 256 booleans per storage slot — far cheaper than a mapping.
    BitMaps.BitMap private _claimed;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Emitted when a new Merkle root is published.
     * @param root     The new Merkle root.
     * @param setBy    Admin address that set the root.
     */
    event MerkleRootSet(bytes32 indexed root, address indexed setBy);

    /**
     * @notice Emitted on every successful claim.
     * @param index    The claimant's index in the Merkle tree.
     * @param account  Address that received the tokens.
     * @param amount   Quantity minted (ERC-721) or copies minted (ERC-1155).
     */
    event Claimed(uint256 indexed index, address indexed account, uint256 amount);

    /**
     * @notice Emitted when the claim window is opened.
     */
    event ClaimOpened(address indexed by);

    /**
     * @notice Emitted when the claim window is closed.
     */
    event ClaimClosed(address indexed by);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Claiming is currently disabled.
    error ClaimNotOpen();

    /// @dev This index has already been claimed.
    error AlreadyClaimed(uint256 index);

    /// @dev The submitted Merkle proof does not verify against the stored root.
    error InvalidProof(uint256 index, address account, uint256 amount);

    /// @dev Merkle root has not been set yet (still bytes32(0)).
    error MerkleRootNotSet();

    /// @dev Zero address passed where a real address is required.
    error ZeroAddress();

    /// @dev Zero amount passed to claim.
    error ZeroAmount();

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param admin_         Address granted DEFAULT_ADMIN_ROLE.
     * @param tokenContract_ NFT contract that will mint tokens to claimers.
     *                       For ERC-721: must have granted AIRDROP_ROLE to this contract
     *                       (claim calls batchMint which requires AIRDROP_ROLE).
     *                       For ERC-1155: must have granted AIRDROP_ROLE to this contract
     *                       (claim calls airdropBatch which requires AIRDROP_ROLE).
     * @param tokenType_     ERC721 or ERC1155.
     * @param tokenId_       For ERC-1155: the token ID to mint. Pass 0 for ERC-721.
     */
    constructor(
        address   admin_,
        address   tokenContract_,
        TokenType tokenType_,
        uint256   tokenId_
    ) {
        if (admin_         == address(0)) revert ZeroAddress();
        if (tokenContract_ == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        tokenContract = tokenContract_;
        tokenType     = tokenType_;
        tokenId       = tokenId_;
        // claimOpen starts false — admin must explicitly open it
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Publish a new Merkle root, replacing the previous one.
     * @dev    Admin only. Changing the root invalidates all outstanding proofs
     *         from the old tree — use with care in production.
     *         Previously claimed indexes remain claimed (bitmap is NOT reset).
     * @param root The new Merkle root.
     */
    function setMerkleRoot(bytes32 root)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(root != bytes32(0), "MerkleAirdrop: zero root");
        merkleRoot = root;
        emit MerkleRootSet(root, msg.sender);
    }

    /**
     * @notice Open the claim window — recipients can now call claim().
     */
    function openClaim() external onlyRole(DEFAULT_ADMIN_ROLE) {
        claimOpen = true;
        emit ClaimOpened(msg.sender);
    }

    /**
     * @notice Close the claim window — claim() will revert until reopened.
     */
    function closeClaim() external onlyRole(DEFAULT_ADMIN_ROLE) {
        claimOpen = false;
        emit ClaimClosed(msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Claim
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Claim tokens by submitting a valid Merkle proof.
     *
     * @dev    Leaf construction MUST match the off-chain tree builder:
     *           leaf = keccak256(abi.encodePacked(index, account, amount))
     *
     *         Double-hashing the leaf (keccak256(keccak256(...))) is a common
     *         pattern to prevent second-preimage attacks in some Merkle
     *         implementations. We use single-hash here to match the murky
     *         library's standard leaf format used in the tests.
     *
     * @param index    Position of this entry in the Merkle tree (0-based).
     * @param account  Address that should receive the tokens.
     * @param amount   Token quantity (ERC-721) or copy count (ERC-1155).
     * @param proof    Array of sibling hashes proving inclusion in the tree.
     */
    function claim(
        uint256          index,
        address          account,
        uint256          amount,
        bytes32[] calldata proof
    ) external {
        // ── Guards ────────────────────────────────────────────────────────────
        if (!claimOpen)              revert ClaimNotOpen();
        if (merkleRoot == bytes32(0)) revert MerkleRootNotSet();
        if (amount == 0)             revert ZeroAmount();
        if (account == address(0))   revert ZeroAddress();

        // ── Double-claim protection ───────────────────────────────────────────
        if (_claimed.get(index)) revert AlreadyClaimed(index);

        // ── Merkle proof verification ─────────────────────────────────────────
        bytes32 leaf = keccak256(abi.encodePacked(index, account, amount));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) {
            revert InvalidProof(index, account, amount);
        }

        // ── Mark claimed BEFORE external call (reentrancy safety) ────────────
        _claimed.set(index);

        // ── Mint tokens ───────────────────────────────────────────────────────
        if (tokenType == TokenType.ERC721) {
            // amount = number of ERC-721 tokens to mint
            address[] memory recipients = new address[](1);
            uint256[] memory quantities = new uint256[](1);
            recipients[0] = account;
            quantities[0] = amount;
            INFT721(tokenContract).batchMint(recipients, quantities);
        } else {
            // amount = copies of tokenId to mint (ERC-1155)
            address[] memory recipients = new address[](1);
            recipients[0] = account;
            INFT1155(tokenContract).airdropBatch(recipients, tokenId, amount);
        }

        emit Claimed(index, account, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Check whether a given index has already been claimed.
     * @param index The index to query (0-based position in the Merkle tree).
     * @return True if already claimed.
     */
    function isClaimed(uint256 index) external view returns (bool) {
        return _claimed.get(index);
    }

    /**
     * @notice Verify whether a proof is valid without executing the claim.
     * @dev    Useful for front-end validation before submitting a transaction.
     * @param index   Index in the tree.
     * @param account Recipient address.
     * @param amount  Token amount.
     * @param proof   Merkle proof.
     * @return True if the proof verifies against the current merkleRoot.
     */
    function verifyProof(
        uint256          index,
        address          account,
        uint256          amount,
        bytes32[] calldata proof
    ) external view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(index, account, amount));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }
}
