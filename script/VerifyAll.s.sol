// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/**
 * @title  VerifyAll
 * @notice Submits all deployed contracts to Etherscan / Polygonscan for
 *         source code verification.
 *
 * -- Why verify? --------------------------------------------------------------
 *   Verified contracts let anyone read the source code on Etherscan,
 *   build trust with users, and allow tools like Tenderly to decode
 *   transactions automatically.
 *
 * -- Usage --------------------------------------------------------------------
 *   Read addresses from the deployment manifest, then run:
 *
 *   NFT721_ADDRESS=0x...          \
 *   NFT1155_ADDRESS=0x...         \
 *   CONTROLLER_ADDRESS=0x...      \
 *   MERKLE_ADDRESS=0x...          \
 *   ADMIN_GUARD_ADDRESS=0x...     \
 *   DEPLOY_ADMIN=0x...            \
 *   forge script script/VerifyAll.s.sol \
 *     --rpc-url $RPC_URL_SEPOLIA \
 *     --etherscan-api-key $ETHERSCAN_API_KEY \
 *     -vvvv
 *
 * -- Alternative: verify each contract manually --------------------------------
 *
 *   forge verify-contract $NFT721_ADDRESS src/tokens/NFT721.sol:NFT721 \
 *     --constructor-args $(cast abi-encode "constructor(string,string,string,uint256,address)" \
 *       "NFT Airdrop Collection" "NAC" "ipfs://..." 0 $DEPLOY_ADMIN) \
 *     --chain-id 11155111 \
 *     --etherscan-api-key $ETHERSCAN_API_KEY
 */
contract VerifyAll is Script {

    function run() external view {
        // -- Read addresses from env -------------------------------------------
        address nft721Addr     = vm.envAddress("NFT721_ADDRESS");
        address nft1155Addr    = vm.envAddress("NFT1155_ADDRESS");
        address controllerAddr = vm.envAddress("CONTROLLER_ADDRESS");
        address merkleAddr     = vm.envAddress("MERKLE_ADDRESS");
        address guardAddr      = vm.envAddress("ADMIN_GUARD_ADDRESS");
        address admin          = vm.envOr("DEPLOY_ADMIN", msg.sender);
        uint256 chainId        = block.chainid;

        string memory chainIdStr = vm.toString(chainId);
        string memory adminStr   = vm.toString(admin);

        // -- Print verification commands ---------------------------------------
        console2.log("=== Verification Commands ===");
        console2.log("Run each command below (or set --verify flag on deploy):");
        console2.log("");

        // 1. NFT721
        console2.log("# 1. NFT721");
        console2.log(string.concat("forge verify-contract ", vm.toString(nft721Addr), " src/tokens/NFT721.sol:NFT721 \\"));
        console2.log(string.concat("  --constructor-args $(cast abi-encode 'constructor(string,string,string,uint256,address)' 'NFT Airdrop Collection' 'NAC' 'ipfs://...' 0 ", adminStr, ") \\"));
        console2.log(string.concat("  --chain-id ", chainIdStr, " --etherscan-api-key $ETHERSCAN_API_KEY"));
        console2.log("");

        // 2. NFT1155
        console2.log("# 2. NFT1155");
        console2.log(string.concat("forge verify-contract ", vm.toString(nft1155Addr), " src/tokens/NFT1155.sol:NFT1155 \\"));
        console2.log(string.concat("  --constructor-args $(cast abi-encode 'constructor(string,string,string,address)' 'NFT Airdrop Editions' 'NAED' 'ipfs://...' ", adminStr, ") \\"));
        console2.log(string.concat("  --chain-id ", chainIdStr, " --etherscan-api-key $ETHERSCAN_API_KEY"));
        console2.log("");

        // 3. AirdropController
        console2.log("# 3. AirdropController");
        console2.log(string.concat("forge verify-contract ", vm.toString(controllerAddr), " src/airdrop/AirdropController.sol:AirdropController \\"));
        console2.log(string.concat("  --constructor-args $(cast abi-encode 'constructor(address,uint256)' ", adminStr, " 500) \\"));
        console2.log(string.concat("  --chain-id ", chainIdStr, " --etherscan-api-key $ETHERSCAN_API_KEY"));
        console2.log("");

        // 4. MerkleAirdrop
        console2.log("# 4. MerkleAirdrop");
        console2.log(string.concat("forge verify-contract ", vm.toString(merkleAddr), " src/airdrop/MerkleAirdrop.sol:MerkleAirdrop \\"));
        console2.log(string.concat("  --constructor-args $(cast abi-encode 'constructor(address,address,uint8,uint256)' ", adminStr, " ", vm.toString(nft721Addr), " 0 0) \\"));
        console2.log(string.concat("  --chain-id ", chainIdStr, " --etherscan-api-key $ETHERSCAN_API_KEY"));
        console2.log("");

        // 5. AdminGuard
        console2.log("# 5. AdminGuard");
        console2.log(string.concat("forge verify-contract ", vm.toString(guardAddr), " src/governance/AdminGuard.sol:AdminGuard \\"));
        console2.log(string.concat("  --constructor-args $(cast abi-encode 'constructor(address,address[],uint256)' ", adminStr, " [<admin1>,<admin2>,<admin3>] 2) \\"));
        console2.log(string.concat("  --chain-id ", chainIdStr, " --etherscan-api-key $ETHERSCAN_API_KEY"));
        console2.log("");

        // -- Alternative: deploy with --verify flag ---------------------------
        console2.log("=== Or use --verify flag during deployment ===");
        console2.log("forge script script/Deploy.s.sol --broadcast --verify \\");
        console2.log("  --etherscan-api-key $ETHERSCAN_API_KEY --rpc-url $RPC_URL_SEPOLIA");
    }
}
