// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";
import {NFT721} from "../src/tokens/NFT721.sol";
import {NFT1155} from "../src/tokens/NFT1155.sol";
import {AirdropController} from "../src/airdrop/AirdropController.sol";
import {MerkleAirdrop} from "../src/airdrop/MerkleAirdrop.sol";
import {AirdropScheduler} from "../src/airdrop/AirdropScheduler.sol";
import {AdminGuard} from "../src/governance/AdminGuard.sol";
import {Deploy} from "../script/Deploy.s.sol";

/**
 * @title  Phase1FinalTest
 * @author NFT Airdrop Platform — P1-I8
 * @notice Phase 1 finalization test suite.
 *
 *   testDeploymentScript  — runs Deploy.s.sol, verifies all addresses non-zero
 *   testRoleConfiguration — after deploy+grant, verifies all role assignments
 *   testEndToEnd          — full flow: deploy → configure → airdrop → verify
 *   testEndToEnd_Merkle   — Merkle claim flow end to end
 *   testEndToEnd_Scheduled— scheduled airdrop with time controls
 *   testEndToEnd_MultiSig — AdminGuard multi-sig cancel flow
 *
 * Run:
 *   forge test --match-contract Phase1FinalTest -vv
 *   forge test --gas-report -vv   (full regression with gas report)
 */
contract Phase1FinalTest is Test {
    // ── Contracts ─────────────────────────────────────────────────────────────
    NFT721 internal nft721;
    NFT1155 internal nft1155;
    AirdropController internal controller;
    MerkleAirdrop internal merkleAirdrop;
    AirdropScheduler internal scheduler;
    AdminGuard internal guard;
    Merkle internal merkle;

    // ── Actors ────────────────────────────────────────────────────────────────
    address internal deployer = makeAddr("deployer");
    address internal admin1 = makeAddr("admin1");
    address internal admin2 = makeAddr("admin2");
    address internal admin3 = makeAddr("admin3");
    address internal operator = makeAddr("operator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    // ── Role constants ─────────────────────────────────────────────────────────
    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // ── Time constants ─────────────────────────────────────────────────────────
    uint256 constant T0 = 1_000_000;
    uint256 constant ONE_HOUR = 3_600;

    // ─────────────────────────────────────────────────────────────────────────
    // setUp — deploy the full stack and wire all roles
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        vm.warp(T0);
        merkle = new Merkle();

        // ── Deploy all contracts ───────────────────────────────────────────────
        address[] memory guardAdmins = new address[](3);
        guardAdmins[0] = admin1;
        guardAdmins[1] = admin2;
        guardAdmins[2] = admin3;

        vm.startPrank(deployer);

        nft721 = new NFT721("Phase1 NFT", "P1NFT", "ipfs://QmP1/", 0, deployer);
        nft1155 = new NFT1155(
            "Phase1 Editions",
            "P1EDT",
            "ipfs://QmP1E/",
            deployer
        );
        controller = new AirdropController(deployer, 500);
        merkleAirdrop = new MerkleAirdrop(
            deployer,
            address(nft721),
            MerkleAirdrop.TokenType.ERC721,
            0
        );
        scheduler = new AirdropScheduler(deployer);
        guard = new AdminGuard(deployer, guardAdmins, 2);

        // ── Wire all roles ─────────────────────────────────────────────────────
        // NFT721 grants
        nft721.grantRole(AIRDROP_ROLE, address(controller));
        nft721.grantRole(AIRDROP_ROLE, address(merkleAirdrop));
        nft721.grantRole(DEFAULT_ADMIN_ROLE, address(guard));

        // NFT1155 grants
        nft1155.grantRole(AIRDROP_ROLE, address(controller));
        nft1155.grantRole(DEFAULT_ADMIN_ROLE, address(guard));

        // Controller grants
        controller.grantRole(AIRDROP_ROLE, operator);
        controller.grantRole(AIRDROP_ROLE, address(scheduler));
        controller.grantRole(DEFAULT_ADMIN_ROLE, address(guard));

        // Scheduler grants
        scheduler.grantRole(KEEPER_ROLE, operator);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testDeploymentScript — runs Deploy.s.sol, verifies all addresses non-zero
    // ─────────────────────────────────────────────────────────────────────────

    function testDeploymentScript() public {
        // Run the Deploy script in test context
        Deploy deployScript = new Deploy();

        // Set env vars the script reads
        vm.setEnv("DEPLOY_ADMIN", vm.toString(deployer));
        vm.setEnv("ADMIN1", vm.toString(admin1));
        vm.setEnv("ADMIN2", vm.toString(admin2));
        vm.setEnv("ADMIN3", vm.toString(admin3));
        vm.setEnv("NFT721_MAX_SUPPLY", "0");
        vm.setEnv("MAX_BATCH_SIZE", "500");
        vm.setEnv("QUORUM", "2");

        Deploy.DeploymentResult memory result = deployScript.run();

        // Verify all addresses are non-zero
        assertTrue(result.nft721 != address(0), "NFT721 is zero");
        assertTrue(result.nft1155 != address(0), "NFT1155 is zero");
        assertTrue(result.controller != address(0), "Controller is zero");
        assertTrue(result.merkleAirdrop != address(0), "MerkleAirdrop is zero");
        assertTrue(result.adminGuard != address(0), "AdminGuard is zero");

        // Verify chainId and deployer are populated
        assertEq(result.chainId, block.chainid);
        assertEq(result.deployer, deployer);
        assertGt(result.deployedAt, 0);

        console2.log("testDeploymentScript: all addresses non-zero. PASS");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testRoleConfiguration — verify all role assignments are correct
    // ─────────────────────────────────────────────────────────────────────────

    function testRoleConfiguration() public view {
        // NFT721 roles
        assertTrue(
            nft721.hasRole(AIRDROP_ROLE, address(controller)),
            "NFT721: controller missing AIRDROP_ROLE"
        );
        assertTrue(
            nft721.hasRole(AIRDROP_ROLE, address(merkleAirdrop)),
            "NFT721: merkle missing AIRDROP_ROLE"
        );
        assertTrue(
            nft721.hasRole(DEFAULT_ADMIN_ROLE, address(guard)),
            "NFT721: guard missing DEFAULT_ADMIN"
        );
        assertTrue(
            nft721.hasRole(DEFAULT_ADMIN_ROLE, deployer),
            "NFT721: deployer should still have admin in setUp"
        );

        // NFT1155 roles
        assertTrue(
            nft1155.hasRole(AIRDROP_ROLE, address(controller)),
            "NFT1155: controller missing AIRDROP_ROLE"
        );
        assertTrue(
            nft1155.hasRole(DEFAULT_ADMIN_ROLE, address(guard)),
            "NFT1155: guard missing DEFAULT_ADMIN"
        );

        // Controller roles
        assertTrue(
            controller.hasRole(AIRDROP_ROLE, operator),
            "Controller: operator missing AIRDROP_ROLE"
        );
        assertTrue(
            controller.hasRole(AIRDROP_ROLE, address(scheduler)),
            "Controller: scheduler missing AIRDROP_ROLE"
        );
        assertTrue(
            controller.hasRole(DEFAULT_ADMIN_ROLE, address(guard)),
            "Controller: guard missing DEFAULT_ADMIN"
        );

        // AdminGuard roles
        assertTrue(
            guard.hasRole(keccak256("ADMIN_ROLE"), admin1),
            "Guard: admin1 missing ADMIN_ROLE"
        );
        assertTrue(
            guard.hasRole(keccak256("ADMIN_ROLE"), admin2),
            "Guard: admin2 missing ADMIN_ROLE"
        );
        assertTrue(
            guard.hasRole(keccak256("ADMIN_ROLE"), admin3),
            "Guard: admin3 missing ADMIN_ROLE"
        );
        assertEq(guard.quorum(), 2);

        console2.log("testRoleConfiguration: all roles correct. PASS");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testEndToEnd — full flow: deploy → configure → airdrop → verify NFT ownership
    // ─────────────────────────────────────────────────────────────────────────

    function testEndToEnd() public {
        console2.log("=== End-to-End Test: Controller Airdrop ===");

        bytes32 jobId = keccak256("e2e-job-001");

        // 1. Create airdrop job
        vm.prank(operator);
        controller.createJob(
            jobId,
            address(nft721),
            AirdropController.TokenType.ERC721,
            0,
            0
        );
        console2.log("[1] Job created:", vm.toString(jobId));

        // 2. Execute airdrop — 3 recipients, 2 tokens each
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;

        vm.prank(operator);
        controller.executeAirdrop721(jobId, recipients, 2, true);
        console2.log("[2] Airdrop executed to 3 recipients");

        // 3. Verify NFT ownership
        assertEq(nft721.balanceOf(alice), 2, "alice should have 2 NFTs");
        assertEq(nft721.balanceOf(bob), 2, "bob should have 2 NFTs");
        assertEq(nft721.balanceOf(carol), 2, "carol should have 2 NFTs");
        assertEq(nft721.totalSupply(), 6, "total supply should be 6");
        console2.log("[3] NFT ownership verified");

        // 4. Verify job completed
        assertEq(
            uint8(controller.getJobStatus(jobId).status),
            uint8(AirdropController.AirdropStatus.Completed)
        );
        console2.log("[4] Job status: Completed");

        console2.log("End-to-End test PASSED.");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testEndToEnd_Merkle — Merkle claim flow end to end
    // ─────────────────────────────────────────────────────────────────────────

    function testEndToEnd_Merkle() public {
        console2.log("=== End-to-End Test: Merkle Claim ===");

        // 1. Build whitelist tree
        address[] memory claimers = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        bytes32[] memory leaves = new bytes32[](3);

        claimers[0] = alice;
        amounts[0] = 2;
        claimers[1] = bob;
        amounts[1] = 1;
        claimers[2] = carol;
        amounts[2] = 3;

        for (uint256 i; i < 3; i++) {
            leaves[i] = keccak256(abi.encodePacked(i, claimers[i], amounts[i]));
        }

        bytes32 root = merkle.getRoot(leaves);
        console2.log("[1] Merkle tree built, root:", vm.toString(root));

        // 2. Admin sets root and opens claims
        vm.startPrank(deployer);
        merkleAirdrop.setMerkleRoot(root);
        merkleAirdrop.openClaim();
        vm.stopPrank();
        console2.log("[2] Root set, claims opened");

        // 3. Alice claims
        bytes32[] memory aliceProof = merkle.getProof(leaves, 0);
        vm.prank(alice);
        merkleAirdrop.claim(0, alice, 2, aliceProof);
        assertEq(nft721.balanceOf(alice), 2, "alice should have 2 NFTs");
        console2.log("[3] Alice claimed 2 NFTs");

        // 4. Bob claims
        bytes32[] memory bobProof = merkle.getProof(leaves, 1);
        vm.prank(bob);
        merkleAirdrop.claim(1, bob, 1, bobProof);
        assertEq(nft721.balanceOf(bob), 1, "bob should have 1 NFT");
        console2.log("[4] Bob claimed 1 NFT");

        // 5. Verify double claim protection
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(MerkleAirdrop.AlreadyClaimed.selector, 0)
        );
        merkleAirdrop.claim(0, alice, 2, aliceProof);
        console2.log("[5] Double claim correctly blocked");

        console2.log("Merkle End-to-End test PASSED.");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testEndToEnd_Scheduled — scheduled airdrop with vm.warp time controls
    // ─────────────────────────────────────────────────────────────────────────

    function testEndToEnd_Scheduled() public {
        console2.log("=== End-to-End Test: Scheduled Airdrop ===");

        uint256 scheduledAt = T0 + ONE_HOUR;
        bytes32 jobId = keccak256("scheduled-e2e-001");
        bytes32 execId = keccak256("exec-e2e-001");

        // 1. Create scheduled job
        vm.prank(operator);
        controller.createJob(
            jobId,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            0
        );
        console2.log("[1] Scheduled job created for T0+1h");

        // 2. Register in scheduler
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        vm.prank(deployer);
        scheduler.scheduleExecution(
            execId,
            jobId,
            address(controller),
            recipients,
            1,
            0,
            true
        );
        console2.log("[2] Execution registered in scheduler");

        // 3. Attempt before time — should be blocked by controller
        vm.warp(scheduledAt - 1);
        vm.prank(operator);
        vm.expectRevert();
        scheduler.triggerExecution(execId);
        console2.log("[3] Early execution correctly blocked");

        // 4. Warp to scheduled time and execute
        vm.warp(scheduledAt);
        vm.prank(operator);
        scheduler.triggerExecution(execId);
        console2.log("[4] Execution triggered at scheduled time");

        // 5. Verify NFTs delivered
        assertEq(nft721.balanceOf(alice), 1, "alice should have 1 NFT");
        assertEq(nft721.balanceOf(bob), 1, "bob should have 1 NFT");
        console2.log("[5] NFTs delivered and verified");

        console2.log("Scheduled End-to-End test PASSED.");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testEndToEnd_MultiSig — AdminGuard multi-sig cancel flow
    // ─────────────────────────────────────────────────────────────────────────

    function testEndToEnd_MultiSig() public {
        console2.log("=== End-to-End Test: Multi-Sig Cancel Job ===");

        bytes32 jobId = keccak256("multisig-e2e-001");
        bytes32 actionId = keccak256("cancel-multisig-e2e-001");

        // 1. Create a job
        vm.prank(operator);
        controller.createJob(
            jobId,
            address(nft721),
            AirdropController.TokenType.ERC721,
            0,
            0
        );
        console2.log("[1] Job created");

        // 2. Propose cancelJob via AdminGuard
        bytes memory callData = abi.encodeWithSignature(
            "cancelJob(bytes32)",
            jobId
        );

        vm.prank(admin1);
        guard.propose(actionId, address(controller), callData);
        console2.log("[2] Cancel action proposed");

        // 3. Admin1 approves — below quorum
        vm.prank(admin1);
        guard.approve(actionId);
        assertFalse(guard.isReady(actionId), "should not be ready yet");
        console2.log("[3] Admin1 approved (1/2)");

        // 4. Admin2 approves — quorum reached
        vm.prank(admin2);
        guard.approve(actionId);
        assertTrue(guard.isReady(actionId), "should be ready now");
        console2.log(unicode"[4] Admin2 approved (2/2) — quorum reached");

        // 5. Execute — anyone can trigger
        guard.execute(actionId);
        console2.log("[5] Action executed");

        // 6. Verify job is cancelled
        assertEq(
            uint8(controller.getJobStatus(jobId).status),
            uint8(AirdropController.AirdropStatus.Failed),
            "job should be Failed after cancel"
        );
        console2.log("[6] Job status verified: Failed (cancelled)");

        console2.log("Multi-Sig End-to-End test PASSED.");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testEndToEnd_1155 — ERC-1155 airdrop end to end
    // ─────────────────────────────────────────────────────────────────────────

    function testEndToEnd_1155() public {
        console2.log("=== End-to-End Test: ERC-1155 Airdrop ===");

        bytes32 jobId = keccak256("1155-e2e-001");

        vm.prank(operator);
        controller.createJob(
            jobId,
            address(nft1155),
            AirdropController.TokenType.ERC1155,
            0,
            0
        );

        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;

        // Airdrop token ID 5, 10 copies each
        vm.prank(operator);
        controller.executeAirdrop1155(jobId, recipients, 5, 10, true);

        assertEq(nft1155.balanceOf(alice, 5), 10);
        assertEq(nft1155.balanceOf(bob, 5), 10);
        assertEq(nft1155.balanceOf(carol, 5), 10);
        assertEq(nft1155.totalMinted(5), 30);

        console2.log("ERC-1155 End-to-End test PASSED.");
    }
}
