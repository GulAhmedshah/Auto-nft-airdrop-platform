// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AdminGuard} from "../src/governance/AdminGuard.sol";
import {AirdropController} from "../src/airdrop/AirdropController.sol";
import {MerkleAirdrop} from "../src/airdrop/MerkleAirdrop.sol";
import {NFT721} from "../src/tokens/NFT721.sol";
import {NFT1155} from "../src/tokens/NFT1155.sol";

/**
 * @title  ConfigureAdmins
 * @notice Deploys AdminGuard and wires it as the sole DEFAULT_ADMIN on every
 *         platform contract. After this script runs, ALL critical admin
 *         operations require multi-sig quorum through AdminGuard.
 *
 * ── What it does ─────────────────────────────────────────────────────────────
 *   1. Reads existing contract addresses from env (or deploys fresh ones)
 *   2. Deploys AdminGuard with 3 admin signers and quorum = 2 (2-of-3)
 *   3. Grants DEFAULT_ADMIN_ROLE on every contract TO AdminGuard
 *   4. Revokes DEFAULT_ADMIN_ROLE from the deployer wallet on every contract
 *      (deployer can no longer act unilaterally)
 *   5. Logs a complete wiring summary
 *
 * ── Usage ────────────────────────────────────────────────────────────────────
 *   ADMIN1=0x... ADMIN2=0x... ADMIN3=0x... \
 *   NFT721_ADDRESS=0x... NFT1155_ADDRESS=0x... \
 *   CONTROLLER_ADDRESS=0x... MERKLE_ADDRESS=0x... \
 *   forge script script/ConfigureAdmins.s.sol \
 *     --rpc-url $RPC_URL_SEPOLIA \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast -vvvv
 *
 * ── After this script ─────────────────────────────────────────────────────────
 *   To cancel a job, the flow is now:
 *     1. AdminGuard.propose(actionId, controllerAddr, cancelJobCalldata)
 *     2. admin1: AdminGuard.approve(actionId)
 *     3. admin2: AdminGuard.approve(actionId)
 *     4. Anyone: AdminGuard.execute(actionId)
 */
contract ConfigureAdmins is Script {
    uint256 constant QUORUM = 2; // 2-of-3

    function run() external {
        address deployer = vm.envOr("DEPLOY_ADMIN", msg.sender);

        // ── Read admin signers from env ───────────────────────────────────────
        address admin1 = vm.envOr("ADMIN1", makeAddr("admin1"));
        address admin2 = vm.envOr("ADMIN2", makeAddr("admin2"));
        address admin3 = vm.envOr("ADMIN3", makeAddr("admin3"));

        address[] memory admins = new address[](3);
        admins[0] = admin1;
        admins[1] = admin2;
        admins[2] = admin3;

        // ── Read or deploy platform contracts ─────────────────────────────────
        address nft721Addr = vm.envOr("NFT721_ADDRESS", address(0));
        address nft1155Addr = vm.envOr("NFT1155_ADDRESS", address(0));
        address controllerAddr = vm.envOr("CONTROLLER_ADDRESS", address(0));
        address merkleAddr = vm.envOr("MERKLE_ADDRESS", address(0));

        vm.startBroadcast();

        // Deploy any missing contracts
        if (nft721Addr == address(0)) {
            nft721Addr = address(
                new NFT721(
                    "Airdrop NFT",
                    "ANFT",
                    "ipfs://QmNFT721/",
                    0,
                    deployer
                )
            );
            console2.log("NFT721 deployed:", nft721Addr);
        }
        if (nft1155Addr == address(0)) {
            nft1155Addr = address(
                new NFT1155(
                    "Airdrop Editions",
                    "AEDT",
                    "ipfs://QmNFT1155/",
                    deployer
                )
            );
            console2.log("NFT1155 deployed:", nft1155Addr);
        }
        if (controllerAddr == address(0)) {
            controllerAddr = address(new AirdropController(deployer, 500));
            console2.log("Controller deployed:", controllerAddr);
        }
        if (merkleAddr == address(0)) {
            merkleAddr = address(
                new MerkleAirdrop(
                    deployer,
                    nft721Addr,
                    MerkleAirdrop.TokenType.ERC721,
                    0
                )
            );
            console2.log("MerkleAirdrop deployed:", merkleAddr);
        }

        // ── Deploy AdminGuard (2-of-3) ────────────────────────────────────────
        AdminGuard guard = new AdminGuard(deployer, admins, QUORUM);
        console2.log("AdminGuard deployed:", address(guard));

        bytes32 adminRole = bytes32(0); // DEFAULT_ADMIN_ROLE = 0x00

        // ── Grant DEFAULT_ADMIN_ROLE on all contracts TO AdminGuard ───────────
        NFT721(nft721Addr).grantRole(adminRole, address(guard));
        NFT1155(nft1155Addr).grantRole(adminRole, address(guard));
        AirdropController(controllerAddr).grantRole(adminRole, address(guard));
        MerkleAirdrop(merkleAddr).grantRole(adminRole, address(guard));

        // ── Revoke DEFAULT_ADMIN_ROLE from deployer on all contracts ──────────
        // After this point the deployer wallet cannot act unilaterally.
        // ALL admin actions require quorum through AdminGuard.
        NFT721(nft721Addr).revokeRole(adminRole, deployer);
        NFT1155(nft1155Addr).revokeRole(adminRole, deployer);
        AirdropController(controllerAddr).revokeRole(adminRole, deployer);
        MerkleAirdrop(merkleAddr).revokeRole(adminRole, deployer);

        vm.stopBroadcast();

        // ── Summary ───────────────────────────────────────────────────────────
        console2.log("\n=== AdminGuard Configuration Complete ===");
        console2.log("AdminGuard  :", address(guard));
        console2.log("Quorum      : 2-of-3");
        console2.log("Admin1      :", admin1);
        console2.log("Admin2      :", admin2);
        console2.log("Admin3      :", admin3);
        console2.log("");
        console2.log("Contracts now guarded by AdminGuard:");
        console2.log("  NFT721          :", nft721Addr);
        console2.log("  NFT1155         :", nft1155Addr);
        console2.log("  AirdropController:", controllerAddr);
        console2.log("  MerkleAirdrop   :", merkleAddr);
        console2.log("");
        console2.log("Deployer admin rights: REVOKED");
        console2.log("Single-wallet admin: NO LONGER POSSIBLE");
        console2.log("");
        console2.log("=== Example: cancel a job via multi-sig ===");
        console2.log(unicode"Step 1 — Propose:");
        console2.log("  AdminGuard.propose(actionId, controllerAddr,");
        console2.log(
            "    abi.encodeWithSignature('cancelJob(bytes32)', jobId))"
        );
        console2.log(
            unicode"Step 2 — Admin1 approves: AdminGuard.approve(actionId)"
        );
        console2.log(
            unicode"Step 3 — Admin2 approves: AdminGuard.approve(actionId)"
        );
        console2.log(
            unicode"Step 4 — Execute:          AdminGuard.execute(actionId)"
        );
    }
}
