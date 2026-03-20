// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {NFT721} from "../src/tokens/NFT721.sol";
import {NFT1155} from "../src/tokens/NFT1155.sol";
import {AirdropController} from "../src/airdrop/AirdropController.sol";
import {MerkleAirdrop} from "../src/airdrop/MerkleAirdrop.sol";
import {AdminGuard} from "../src/governance/AdminGuard.sol";

/**
 * @title  Deploy
 * @author NFT Airdrop Platform — P1-I8
 * @notice Single-command deployment of the entire NFT Airdrop Platform.
 *
 * ── Deployment order (dependency graph) ─────────────────────────────────────
 *
 *   1. NFT721            — no dependencies
 *   2. NFT1155           — no dependencies
 *   3. AirdropController — no dependencies
 *   4. MerkleAirdrop     — depends on NFT721 (needs tokenContract address)
 *   5. AdminGuard        — depends on all above (wraps their admin roles)
 *
 * ── After deployment ─────────────────────────────────────────────────────────
 *   Run GrantRoles.s.sol to wire all role assignments.
 *   Run VerifyAll.s.sol to verify contracts on Etherscan.
 *
 * ── Usage — local anvil ──────────────────────────────────────────────────────
 *   anvil  (in a separate terminal)
 *   forge script script/Deploy.s.sol \
 *     --rpc-url $RPC_URL_LOCAL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast -vvvv
 *
 * ── Usage — Sepolia testnet ───────────────────────────────────────────────────
 *   forge script script/Deploy.s.sol \
 *     --rpc-url $RPC_URL_SEPOLIA \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY \
 *     -vvvv
 *
 * ── Environment variables ─────────────────────────────────────────────────────
 *   DEPLOY_ADMIN     — admin wallet (defaults to msg.sender)
 *   NFT721_NAME      — token name   (defaults to "NFT Airdrop Collection")
 *   NFT721_SYMBOL    — token symbol (defaults to "NAC")
 *   NFT721_BASE_URI  — IPFS base URI
 *   NFT721_MAX_SUPPLY — max supply, 0 = unlimited
 *   NFT1155_NAME     — 1155 collection name
 *   NFT1155_SYMBOL   — 1155 symbol
 *   NFT1155_BASE_URI — IPFS base URI
 *   MAX_BATCH_SIZE   — AirdropController batch limit (default 500)
 *   QUORUM           — AdminGuard quorum (default 2)
 *   ADMIN1, ADMIN2, ADMIN3 — AdminGuard signers
 */
contract Deploy is Script {
    // ── Deployment result struct — passed between internal functions ──────────
    struct DeploymentResult {
        address nft721;
        address nft1155;
        address controller;
        address merkleAirdrop;
        address adminGuard;
        uint256 chainId;
        address deployer;
        uint256 deployedAt;
    }

    function run() external returns (DeploymentResult memory result) {
        // ── Read config from env ──────────────────────────────────────────────
        address admin = vm.envOr("DEPLOY_ADMIN", msg.sender);

        string memory nft721Name = vm.envOr(
            "NFT721_NAME",
            string("NFT Airdrop Collection")
        );
        string memory nft721Symbol = vm.envOr("NFT721_SYMBOL", string("NAC"));
        string memory nft721BaseURI = vm.envOr(
            "NFT721_BASE_URI",
            string("ipfs://QmNFT721BaseURI/")
        );
        uint256 nft721MaxSupply = vm.envOr("NFT721_MAX_SUPPLY", uint256(0));

        string memory nft1155Name = vm.envOr(
            "NFT1155_NAME",
            string("NFT Airdrop Editions")
        );
        string memory nft1155Symbol = vm.envOr(
            "NFT1155_SYMBOL",
            string("NAED")
        );
        string memory nft1155BaseURI = vm.envOr(
            "NFT1155_BASE_URI",
            string("ipfs://QmNFT1155BaseURI/")
        );

        uint256 maxBatchSize = vm.envOr("MAX_BATCH_SIZE", uint256(500));
        uint256 quorum = vm.envOr("QUORUM", uint256(2));

        address admin1 = vm.envOr("ADMIN1", admin);
        address admin2 = vm.envOr("ADMIN2", admin);
        address admin3 = vm.envOr("ADMIN3", admin);

        address[] memory guardAdmins = new address[](3);
        guardAdmins[0] = admin1;
        guardAdmins[1] = admin2;
        guardAdmins[2] = admin3;

        // ── Deploy ────────────────────────────────────────────────────────────
        vm.startBroadcast();

        // 1. NFT721
        NFT721 nft721 = new NFT721(
            nft721Name,
            nft721Symbol,
            nft721BaseURI,
            nft721MaxSupply,
            admin
        );
        console2.log("[1/5] NFT721 deployed          :", address(nft721));

        // 2. NFT1155
        NFT1155 nft1155 = new NFT1155(
            nft1155Name,
            nft1155Symbol,
            nft1155BaseURI,
            admin
        );
        console2.log("[2/5] NFT1155 deployed         :", address(nft1155));

        // 3. AirdropController
        AirdropController controller = new AirdropController(
            admin,
            maxBatchSize
        );
        console2.log("[3/5] AirdropController deployed:", address(controller));

        // 4. MerkleAirdrop (ERC-721 variant — root set later via setMerkleRoot)
        MerkleAirdrop merkleAirdrop = new MerkleAirdrop(
            admin,
            address(nft721),
            MerkleAirdrop.TokenType.ERC721,
            0
        );
        console2.log(
            "[4/5] MerkleAirdrop deployed   :",
            address(merkleAirdrop)
        );

        // 5. AdminGuard
        AdminGuard adminGuard = new AdminGuard(admin, guardAdmins, quorum);
        console2.log("[5/5] AdminGuard deployed      :", address(adminGuard));

        vm.stopBroadcast();

        // ── Populate result ───────────────────────────────────────────────────
        result = DeploymentResult({
            nft721: address(nft721),
            nft1155: address(nft1155),
            controller: address(controller),
            merkleAirdrop: address(merkleAirdrop),
            adminGuard: address(adminGuard),
            chainId: block.chainid,
            deployer: admin,
            deployedAt: block.timestamp
        });

        // ── Write deployments/<chainId>.json ─────────────────────────────────
        _writeDeploymentManifest(result);

        // ── Print summary ─────────────────────────────────────────────────────
        _printSummary(result);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal — write deployment manifest JSON
    // ─────────────────────────────────────────────────────────────────────────

    function _writeDeploymentManifest(DeploymentResult memory r) internal {
        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "chainId": ',
                vm.toString(r.chainId),
                ",\n",
                '  "deployedAt": ',
                vm.toString(r.deployedAt),
                ",\n",
                '  "deployer": "',
                vm.toString(r.deployer),
                '",\n',
                '  "contracts": {\n',
                '    "NFT721": "',
                vm.toString(r.nft721),
                '",\n',
                '    "NFT1155": "',
                vm.toString(r.nft1155),
                '",\n',
                '    "AirdropController": "',
                vm.toString(r.controller),
                '",\n',
                '    "MerkleAirdrop": "',
                vm.toString(r.merkleAirdrop),
                '",\n',
                '    "AdminGuard": "',
                vm.toString(r.adminGuard),
                '"\n',
                "  }\n",
                "}"
            )
        );

        string memory path = string(
            abi.encodePacked("deployments/", vm.toString(r.chainId), ".json")
        );

        vm.writeFile(path, json);
        console2.log("Deployment manifest saved to:", path);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal — print human-readable summary
    // ─────────────────────────────────────────────────────────────────────────

    function _printSummary(DeploymentResult memory r) internal pure {
        console2.log("=== NFT AIRDROP PLATFORM DEPLOYED ===");
        console2.log("Chain ID :", r.chainId);
        console2.log("Deployer :", r.deployer);
        console2.log("NFT721   :", r.nft721);
        console2.log("NFT1155  :", r.nft1155);
        console2.log("Controller:", r.controller);
        console2.log("Merkle   :", r.merkleAirdrop);
        console2.log("Guard    :", r.adminGuard);
        console2.log("NEXT: run script/GrantRoles.s.sol");
    }
}
