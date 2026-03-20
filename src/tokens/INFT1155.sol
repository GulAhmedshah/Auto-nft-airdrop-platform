// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title  INFT1155
 * @notice Minimal interface the AirdropController uses to talk to NFT1155.
 *
 * The controller only needs two things from NFT1155:
 *   1. airdropBatch — to push the same token ID to many recipients
 *   2. hasRole      — to verify the controller has AIRDROP_ROLE
 */
interface INFT1155 {
    /**
     * @notice Mint `amountEach` copies of token `id` to every address in `recipients`.
     * @dev    Caller must hold AIRDROP_ROLE on the NFT1155 contract.
     * @param recipients Array of recipient addresses.
     * @param id         Token ID to distribute.
     * @param amountEach Amount each recipient receives.
     */
    function airdropBatch(
        address[] calldata recipients,
        uint256 id,
        uint256 amountEach
    ) external;

    /**
     * @notice Check whether `account` has `role` on the NFT1155 contract.
     * @param role    Role identifier (bytes32 hash).
     * @param account Address to check.
     * @return True if account has the role.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);
}
