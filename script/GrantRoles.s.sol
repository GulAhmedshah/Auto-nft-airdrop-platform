// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {NFT721} from "../src/tokens/NFT721.sol";
import {NFT1155} from "../src/tokens/NFT1155.sol";
import {AirdropController} from "../src/airdrop/AirdropController.sol";
import {MerkleAirdrop} from "../src/airdrop/MerkleAirdrop.sol";
import {AdminGuard} from "../src/governance/AdminGuard.sol";

/**
 * @title  GrantRoles
 * @notice Post-deployment role configuration script.
 *         Run this immediately after Deploy.s.sol to wire all inter-contract
 *         roles and transfer admin control to AdminGuard.
 *
 * ── Role wiring performed ────────────────────────────────────────────────────
 *
 *   NFT721:
 *     AIRDROP_ROLE  → AirdropController  (so controller can call batchMint)
 *     AIRDROP_ROLE  → MerkleAirdrop      (so merkle claimer can call batchMint)
 *     DEFAULT_ADMIN → AdminGuard         (all admin ops now need multi-sig)
 *     DEFAULT_ADMIN revoked from deployer
 *
 *   NFT1155:
 *     AIRDROP_ROLE  → AirdropController  (so controller can call airdropBatch)
 *     DEFAULT_ADMIN → AdminGuard
 *     DEFAULT_ADMIN revoked from deployer
 *
 *   AirdropController:
 *     DEFAULT_ADMIN → AdminGuard
 *     DEFAULT_ADMIN revoked from deployer
 *
 *   MerkleAirdrop:
 *     DEFAULT_ADMIN → AdminGuard
 *     DEFAULT_ADMIN revoked from deployer
 *
 * ── Usage ────────────────────────────────────────────────────────────────────
 *   Read addresses from the deployment manifest:
 *
 *   NFT721_ADDRESS=0x...      \
 *   NFT1155_ADDRESS=0x...     \
 *   CONTROLLER_ADDRESS=0x...  \
 *   MERKLE_ADDRESS=0x...      \
 *   ADMIN_GUARD_ADDRESS=0x... \
 *   forge script script/GrantRoles.s.sol \
 *     --rpc-url $RPC_URL_SEPOLIA \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast -vvvv
 */
contract GrantRoles is Script {
    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");

    function run() external {
        // ── Read addresses from env ───────────────────────────────────────────
        address deployer = vm.envOr("DEPLOY_ADMIN", msg.sender);
        address nft721Addr = vm.envAddress("NFT721_ADDRESS");
        address nft1155Addr = vm.envAddress("NFT1155_ADDRESS");
        address controllerAddr = vm.envAddress("CONTROLLER_ADDRESS");
        address merkleAddr = vm.envAddress("MERKLE_ADDRESS");
        address guardAddr = vm.envAddress("ADMIN_GUARD_ADDRESS");

        NFT721 nft721 = NFT721(nft721Addr);
        NFT1155 nft1155 = NFT1155(nft1155Addr);
        AirdropController controller = AirdropController(controllerAddr);
        MerkleAirdrop merkle = MerkleAirdrop(merkleAddr);

        vm.startBroadcast();

        // ── NFT721 role grants ────────────────────────────────────────────────
        console2.log("Configuring NFT721...");
        nft721.grantRole(AIRDROP_ROLE, controllerAddr); // controller → batchMint
        nft721.grantRole(AIRDROP_ROLE, merkleAddr); // merkle     → batchMint
        nft721.grantRole(DEFAULT_ADMIN_ROLE, guardAddr); // guard becomes admin
        nft721.revokeRole(DEFAULT_ADMIN_ROLE, deployer); // deployer loses admin

        // ── NFT1155 role grants ───────────────────────────────────────────────
        console2.log("Configuring NFT1155...");
        nft1155.grantRole(AIRDROP_ROLE, controllerAddr);
        nft1155.grantRole(DEFAULT_ADMIN_ROLE, guardAddr);
        nft1155.revokeRole(DEFAULT_ADMIN_ROLE, deployer);

        // ── AirdropController role grants ─────────────────────────────────────
        console2.log("Configuring AirdropController...");
        controller.grantRole(DEFAULT_ADMIN_ROLE, guardAddr);
        controller.revokeRole(DEFAULT_ADMIN_ROLE, deployer);

        // ── MerkleAirdrop role grants ─────────────────────────────────────────
        console2.log("Configuring MerkleAirdrop...");
        merkle.grantRole(DEFAULT_ADMIN_ROLE, guardAddr);
        merkle.revokeRole(DEFAULT_ADMIN_ROLE, deployer);

        vm.stopBroadcast();

        // ── Verification summary ──────────────────────────────────────────────
        console2.log("\n=== Role Configuration Complete ===");
        console2.log(
            unicode"NFT721.AIRDROP_ROLE → Controller :",
            nft721.hasRole(AIRDROP_ROLE, controllerAddr)
        );
        console2.log(
            unicode"NFT721.AIRDROP_ROLE → Merkle     :",
            nft721.hasRole(AIRDROP_ROLE, merkleAddr)
        );
        console2.log(
            unicode"NFT721.ADMIN_ROLE   → Guard      :",
            nft721.hasRole(DEFAULT_ADMIN_ROLE, guardAddr)
        );
        console2.log(
            unicode"NFT721.ADMIN_ROLE   → Deployer   :",
            nft721.hasRole(DEFAULT_ADMIN_ROLE, deployer)
        );
        console2.log("---");
        console2.log(
            unicode"NFT1155.AIRDROP_ROLE → Controller:",
            nft1155.hasRole(AIRDROP_ROLE, controllerAddr)
        );
        console2.log(
            unicode"NFT1155.ADMIN_ROLE   → Guard     :",
            nft1155.hasRole(DEFAULT_ADMIN_ROLE, guardAddr)
        );
        console2.log(
            unicode"NFT1155.ADMIN_ROLE   → Deployer  :",
            nft1155.hasRole(DEFAULT_ADMIN_ROLE, deployer)
        );
        console2.log("---");
        console2.log(
            unicode"Controller.ADMIN_ROLE → Guard    :",
            controller.hasRole(DEFAULT_ADMIN_ROLE, guardAddr)
        );
        console2.log(
            unicode"Controller.ADMIN_ROLE → Deployer :",
            controller.hasRole(DEFAULT_ADMIN_ROLE, deployer)
        );
        console2.log("---");
        console2.log(
            unicode"Merkle.ADMIN_ROLE → Guard        :",
            merkle.hasRole(DEFAULT_ADMIN_ROLE, guardAddr)
        );
        console2.log(
            unicode"Merkle.ADMIN_ROLE → Deployer     :",
            merkle.hasRole(DEFAULT_ADMIN_ROLE, deployer)
        );
        console2.log(
            "\nAll admin control transferred to AdminGuard (multi-sig)."
        );
    }
}
