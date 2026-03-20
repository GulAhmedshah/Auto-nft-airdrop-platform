// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title  INFT721
 * @notice Minimal interface the AirdropController uses to talk to NFT721.
 *
 * Why an interface and not a direct import?
 * ─────────────────────────────────────────
 * The controller is a standalone contract. It should NOT be coupled to the
 * full NFT721 implementation. Using an interface means:
 *   • The controller compiles without needing NFT721's source code.
 *   • Any ERC-721A contract that exposes these functions is compatible.
 *   • Easier to upgrade or swap the token contract later.
 *
 * The controller only needs two things from NFT721:
 *   1. batchMint  — to push tokens to many recipients
 *   2. hasRole    — to verify the controller has AIRDROP_ROLE before executing
 */
interface INFT721 {
    /**
     * @notice Mint `quantities[i]` tokens to `recipients[i]` for each index.
     * @dev    Caller must hold AIRDROP_ROLE on the NFT721 contract.
     * @param recipients Array of recipient addresses.
     * @param quantities Corresponding token quantities per recipient.
     */
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata quantities
    ) external;

    /**
     * @notice  Check whether `account` has `role` on the NFT721 contract.
     * @param role    Role identifier (bytes32 hash).
     * @param account Address to check.
     * @return True if account has the role.
     */
    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);
}
