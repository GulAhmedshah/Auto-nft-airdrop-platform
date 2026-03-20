// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2}     from "forge-std/Script.sol";
import {AirdropController}    from "../src/airdrop/AirdropController.sol";
import {AirdropScheduler}     from "../src/airdrop/AirdropScheduler.sol";
import {NFT721}               from "../src/tokens/NFT721.sol";

/**
 * @title  ScheduleAirdrop
 * @notice Demo script that deploys the full stack and schedules a future airdrop.
 *
 * ── What it does ─────────────────────────────────────────────────────────────
 *   1. Deploys NFT721, AirdropController, AirdropScheduler
 *   2. Wires roles between the contracts
 *   3. Creates a Controller job scheduled 1 hour from now, expiring in 24 hours
 *   4. Registers a batch execution in the Scheduler
 *   5. Logs all relevant addresses and the jobId for follow-up
 *
 * ── Usage ────────────────────────────────────────────────────────────────────
 *   forge script script/ScheduleAirdrop.s.sol \
 *     --rpc-url $RPC_URL_LOCAL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast -vvvv
 *
 * ── After deployment ─────────────────────────────────────────────────────────
 *   At scheduledAt time, the keeper (or manually) calls:
 *     cast send $SCHEDULER "performUpkeep(bytes)" \
 *       $(cast abi-encode "f(bytes32)" $EXECUTION_ID) \
 *       --rpc-url $RPC_URL_LOCAL \
 *       --private-key $PRIVATE_KEY
 */
contract ScheduleAirdrop is Script {

    uint256 constant MAX_BATCH = 500;

    // Sample recipients for the demo
    address[] internal RECIPIENTS;

    function run() external {
        address admin = vm.envOr("DEPLOY_ADMIN", msg.sender);

        RECIPIENTS.push(address(0xBEEF01));
        RECIPIENTS.push(address(0xBEEF02));
        RECIPIENTS.push(address(0xBEEF03));
        RECIPIENTS.push(address(0xBEEF04));
        RECIPIENTS.push(address(0xBEEF05));

        vm.startBroadcast();

        // ── 1. Deploy NFT721 ──────────────────────────────────────────────────
        NFT721 nft = new NFT721(
            "Scheduled Airdrop NFT",
            "SANFT",
            "ipfs://QmScheduled/",
            0,
            admin
        );

        // ── 2. Deploy AirdropController ───────────────────────────────────────
        AirdropController controller = new AirdropController(admin, MAX_BATCH);

        // ── 3. Deploy AirdropScheduler ────────────────────────────────────────
        AirdropScheduler scheduler = new AirdropScheduler(admin);

        // ── 4. Wire roles ─────────────────────────────────────────────────────
        bytes32 airdropRole = keccak256("AIRDROP_ROLE");

        // Controller needs AIRDROP_ROLE on NFT
        nft.grantRole(airdropRole, address(controller));

        // Scheduler needs AIRDROP_ROLE on Controller to call execute functions
        controller.grantRole(airdropRole, address(scheduler));

        // ── 5. Create scheduled Controller job ───────────────────────────────
        bytes32 jobId       = keccak256("demo-scheduled-airdrop-001");
        uint256 scheduledAt = block.timestamp + 1 hours;   // execute after 1h
        uint256 expiresAt   = block.timestamp + 24 hours;  // expire after 24h

        controller.createJob(
            jobId,
            address(nft),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            expiresAt
        );

        // ── 6. Register batch execution in Scheduler ─────────────────────────
        bytes32 executionId = keccak256("demo-execution-001");

        scheduler.scheduleExecution(
            executionId,
            jobId,
            address(controller),
            RECIPIENTS,
            2,      // 2 tokens per recipient
            0,      // tokenId (ignored for ERC-721)
            true    // isFinalBatch
        );

        vm.stopBroadcast();

        // ── Summary ───────────────────────────────────────────────────────────
        console2.log("=== Scheduled Airdrop Demo Deployed ===");
        console2.log("NFT721           :", address(nft));
        console2.log("AirdropController:", address(controller));
        console2.log("AirdropScheduler :", address(scheduler));
        console2.log("Job ID           :", vm.toString(jobId));
        console2.log("Execution ID     :", vm.toString(executionId));
        console2.log("Scheduled At     :", scheduledAt, "(now +1h)");
        console2.log("Expires At       :", expiresAt,   "(now +24h)");
        console2.log("Recipients       :", RECIPIENTS.length);
        console2.log("");
        console2.log("=== To trigger manually after scheduledAt ===");
        console2.log("cast send", address(scheduler),
            '"performUpkeep(bytes)"',
            vm.toString(abi.encode(executionId)));
    }
}
