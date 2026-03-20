// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AirdropController} from "../src/airdrop/AirdropController.sol";
import {AirdropScheduler} from "../src/airdrop/AirdropScheduler.sol";
import {Vm} from "forge-std/Vm.sol";
import {NFT721} from "../src/tokens/NFT721.sol";
import {NFT1155} from "../src/tokens/NFT1155.sol";

/**
 * @title  AirdropSchedulerTest
 * @notice Foundry tests for P1-I6 time controls and scheduling.
 *
 * Key testing tool — vm.warp(timestamp):
 *   Sets block.timestamp to any value you specify.
 *   This lets us test "1 second before scheduledAt" and
 *   "exactly at scheduledAt" without waiting real time.
 *
 * Run:
 *   forge test --match-contract AirdropSchedulerTest -vv
 */
contract AirdropSchedulerTest is Test {
    // ── Contracts ────────────────────────────────────────────────────────────
    AirdropController internal controller;
    AirdropScheduler internal scheduler;
    NFT721 internal nft721;
    NFT1155 internal nft1155;

    // ── Actors ───────────────────────────────────────────────────────────────
    address internal admin = makeAddr("admin");
    address internal airdropAgent = makeAddr("airdropAgent");
    address internal nobody = makeAddr("nobody");

    // ── Role constants ────────────────────────────────────────────────────────
    bytes32 constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");
    bytes32 constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // ── Time constants ────────────────────────────────────────────────────────
    uint256 constant T0 = 1_000_000; // anvil start timestamp
    uint256 constant ONE_HOUR = 3_600;
    uint256 constant ONE_DAY = 86_400;

    // ── Reusable job IDs ─────────────────────────────────────────────────────
    bytes32 constant JOB_A = keccak256("job-alpha");
    bytes32 constant JOB_B = keccak256("job-beta");
    bytes32 constant JOB_C = keccak256("job-gamma");

    // ─────────────────────────────────────────────────────────────────────────
    // Setup
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        // Pin block.timestamp to T0 so all tests start from a known baseline
        vm.warp(T0);

        // Deploy contracts
        nft721 = new NFT721("Test NFT", "TNFT", "ipfs://x/", 0, admin);
        nft1155 = new NFT1155("Test Editions", "TEDT", "ipfs://y/", admin);
        controller = new AirdropController(admin, 500);
        scheduler = new AirdropScheduler(admin);

        // Wire roles
        vm.startPrank(admin);

        // Controller needs AIRDROP_ROLE on both token contracts
        nft721.grantRole(AIRDROP_ROLE, address(controller));
        nft1155.grantRole(AIRDROP_ROLE, address(controller));

        // Scheduler needs AIRDROP_ROLE on Controller
        controller.grantRole(AIRDROP_ROLE, address(scheduler));

        // Grant AIRDROP_ROLE on Controller to airdropAgent for direct tests
        controller.grantRole(AIRDROP_ROLE, airdropAgent);

        // Grant KEEPER_ROLE on Scheduler to airdropAgent
        scheduler.grantRole(KEEPER_ROLE, airdropAgent);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper — create a simple recipient array
    // ─────────────────────────────────────────────────────────────────────────

    function _recipients(
        uint256 n
    ) internal pure returns (address[] memory arr) {
        arr = new address[](n);
        for (uint256 i; i < n; i++) {
            arr[i] = address(uint160(0xCAFE + i));
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testImmediateExecution — scheduledAt=0 executes without warp
    // ─────────────────────────────────────────────────────────────────────────

    function testImmediateExecution() public {
        // scheduledAt=0, expiresAt=0  →  no time restrictions at all
        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            0, // immediate
            0 // no expiry
        );

        // Execute right away — should succeed with no warp
        vm.prank(airdropAgent);
        controller.executeAirdrop721(JOB_A, _recipients(3), 1, true);

        AirdropController.AirdropJob memory job = controller.getJobStatus(
            JOB_A
        );
        assertEq(
            uint8(job.status),
            uint8(AirdropController.AirdropStatus.Completed)
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testExecuteTooEarly — warp to T-1, expect TooEarly revert
    // ─────────────────────────────────────────────────────────────────────────

    function testExecuteTooEarly() public {
        uint256 scheduledAt = T0 + ONE_HOUR; // 1 hour from now

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            0
        );

        // Warp to exactly 1 second BEFORE scheduledAt
        vm.warp(scheduledAt - 1);

        vm.prank(airdropAgent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AirdropController.TooEarly.selector,
                JOB_A,
                scheduledAt,
                scheduledAt - 1
            )
        );
        controller.executeAirdrop721(JOB_A, _recipients(2), 1, true);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testExecuteOnTime — warp to scheduledAt exactly, expect success
    // ─────────────────────────────────────────────────────────────────────────

    function testExecuteOnTime() public {
        uint256 scheduledAt = T0 + ONE_HOUR;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            0
        );

        // Warp to EXACTLY scheduledAt
        vm.warp(scheduledAt);

        vm.prank(airdropAgent);
        controller.executeAirdrop721(JOB_A, _recipients(3), 1, true);

        AirdropController.AirdropJob memory job = controller.getJobStatus(
            JOB_A
        );
        assertEq(
            uint8(job.status),
            uint8(AirdropController.AirdropStatus.Completed)
        );
        assertEq(nft721.balanceOf(_recipients(3)[0]), 1);
    }

    function testExecuteAfterScheduledAt() public {
        uint256 scheduledAt = T0 + ONE_HOUR;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            0
        );

        // Warp 2 hours ahead — still within the (no) expiry window
        vm.warp(T0 + 2 * ONE_HOUR);

        vm.prank(airdropAgent);
        controller.executeAirdrop721(JOB_A, _recipients(2), 1, true);

        assertEq(
            uint8(controller.getJobStatus(JOB_A).status),
            uint8(AirdropController.AirdropStatus.Completed)
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testExpiredJob — warp past expiresAt, expect Expired revert
    // ─────────────────────────────────────────────────────────────────────────

    function testExpiredJob() public {
        uint256 scheduledAt = T0 + ONE_HOUR;
        uint256 expiresAt = T0 + ONE_DAY;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            expiresAt
        );

        // Warp to exactly 1 second AFTER expiresAt
        vm.warp(expiresAt + 1);

        vm.prank(airdropAgent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AirdropController.JobExpired.selector,
                JOB_A,
                expiresAt,
                expiresAt + 1
            )
        );
        controller.executeAirdrop721(JOB_A, _recipients(2), 1, true);
    }

    function testExecuteAtExpiryBoundary() public {
        uint256 scheduledAt = T0 + ONE_HOUR;
        uint256 expiresAt = T0 + ONE_DAY;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            expiresAt
        );

        // Warp to EXACTLY expiresAt — should still succeed
        vm.warp(expiresAt);

        vm.prank(airdropAgent);
        controller.executeAirdrop721(JOB_A, _recipients(2), 1, true);

        assertEq(
            uint8(controller.getJobStatus(JOB_A).status),
            uint8(AirdropController.AirdropStatus.Completed)
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testCancelJob — cancel pending, try execute, expect revert
    // ─────────────────────────────────────────────────────────────────────────

    function testCancelJob() public {
        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            T0 + ONE_HOUR,
            0
        );

        // Admin cancels before scheduledAt
        vm.prank(admin);
        controller.cancelJob(JOB_A);

        AirdropController.AirdropJob memory job = controller.getJobStatus(
            JOB_A
        );
        assertEq(
            uint8(job.status),
            uint8(AirdropController.AirdropStatus.Failed)
        );

        // Warp past scheduledAt — execute should still revert (job is Failed)
        vm.warp(T0 + ONE_HOUR + 1);

        vm.prank(airdropAgent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AirdropController.JobNotExecutable.selector,
                JOB_A,
                AirdropController.AirdropStatus.Failed
            )
        );
        controller.executeAirdrop721(JOB_A, _recipients(2), 1, true);
    }

    function testCancelJobEmitsEvent() public {
        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            0,
            0
        );

        vm.expectEmit(true, true, false, false, address(controller));
        emit AirdropController.JobCancelled(JOB_A, admin);

        vm.prank(admin);
        controller.cancelJob(JOB_A);
    }

    function testCannotCancelCompletedJob() public {
        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            0,
            0
        );

        vm.prank(airdropAgent);
        controller.executeAirdrop721(JOB_A, _recipients(2), 1, true);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                AirdropController.JobNotCancellable.selector,
                JOB_A,
                AirdropController.AirdropStatus.Completed
            )
        );
        controller.cancelJob(JOB_A);
    }

    function testNonAdminCannotCancel() public {
        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            0,
            0
        );

        vm.prank(nobody);
        vm.expectRevert();
        controller.cancelJob(JOB_A);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testReschedule — reschedule pending job, execute at new time
    // ─────────────────────────────────────────────────────────────────────────

    function testReschedule() public {
        uint256 originalScheduledAt = T0 + ONE_HOUR;
        uint256 newScheduledAt = T0 + 2 * ONE_HOUR;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            originalScheduledAt,
            0
        );

        // Reschedule to 2 hours from now
        vm.prank(airdropAgent);
        controller.rescheduleJob(JOB_A, newScheduledAt);

        AirdropController.AirdropJob memory job = controller.getJobStatus(
            JOB_A
        );
        assertEq(job.scheduledAt, newScheduledAt);

        // Warp to original time — still too early for new schedule
        vm.warp(originalScheduledAt);

        vm.prank(airdropAgent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AirdropController.TooEarly.selector,
                JOB_A,
                newScheduledAt,
                originalScheduledAt
            )
        );
        controller.executeAirdrop721(JOB_A, _recipients(2), 1, true);

        // Warp to new scheduled time — now it should succeed
        vm.warp(newScheduledAt);

        vm.prank(airdropAgent);
        controller.executeAirdrop721(JOB_A, _recipients(2), 1, true);

        assertEq(
            uint8(controller.getJobStatus(JOB_A).status),
            uint8(AirdropController.AirdropStatus.Completed)
        );
    }

    function testRescheduleEmitsEvent() public {
        uint256 original = T0 + ONE_HOUR;
        uint256 newTime = T0 + 2 * ONE_HOUR;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            original,
            0
        );

        vm.expectEmit(true, false, false, true, address(controller));
        emit AirdropController.JobRescheduled(JOB_A, original, newTime);

        vm.prank(airdropAgent);
        controller.rescheduleJob(JOB_A, newTime);
    }

    function testCannotRescheduleInProgressJob() public {
        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            0,
            0
        );

        // Start execution (not final batch)
        vm.prank(airdropAgent);
        controller.executeAirdrop721(JOB_A, _recipients(2), 1, false);

        vm.prank(airdropAgent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AirdropController.JobNotReschedulable.selector,
                JOB_A,
                AirdropController.AirdropStatus.InProgress
            )
        );
        controller.rescheduleJob(JOB_A, T0 + ONE_HOUR);
    }

    function testRescheduleToImmediateAllowed() public {
        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            T0 + ONE_HOUR,
            0
        );

        // Reschedule to 0 (immediate)
        vm.prank(airdropAgent);
        controller.rescheduleJob(JOB_A, 0);

        assertEq(controller.getJobStatus(JOB_A).scheduledAt, 0);

        // Should execute right now without warp
        vm.prank(airdropAgent);
        controller.executeAirdrop721(JOB_A, _recipients(2), 1, true);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AirdropScheduled event
    // ─────────────────────────────────────────────────────────────────────────

    function testAirdropScheduledEventEmitted() public {
        uint256 scheduledAt = T0 + ONE_HOUR;
        uint256 expiresAt = T0 + ONE_DAY;

        vm.expectEmit(true, false, false, true, address(controller));
        emit AirdropController.AirdropScheduled(JOB_A, scheduledAt, expiresAt);

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            expiresAt
        );
    }

    function testNoAirdropScheduledEventForImmediateJob() public {
        // For immediate jobs (scheduledAt=0, expiresAt=0)
        // AirdropScheduled event should NOT be emitted
        vm.recordLogs();

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            0,
            0
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 scheduledSig = keccak256(
            "AirdropScheduled(bytes32,uint256,uint256)"
        );

        for (uint256 i; i < logs.length; i++) {
            assertNotEq(
                logs[i].topics[0],
                scheduledSig,
                "AirdropScheduled should not fire for immediate jobs"
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invalid time config
    // ─────────────────────────────────────────────────────────────────────────

    function testExpiryBeforeScheduledAtReverts() public {
        uint256 scheduledAt = T0 + 2 * ONE_HOUR;
        uint256 expiresAt = T0 + ONE_HOUR; // expires BEFORE it starts

        vm.prank(airdropAgent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AirdropController.InvalidExpiryTime.selector,
                scheduledAt,
                expiresAt
            )
        );
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            expiresAt
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ERC-1155 time controls
    // ─────────────────────────────────────────────────────────────────────────

    function testExecute1155TooEarly() public {
        uint256 scheduledAt = T0 + ONE_HOUR;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_B,
            address(nft1155),
            AirdropController.TokenType.ERC1155,
            scheduledAt,
            0
        );

        vm.warp(scheduledAt - 1);

        vm.prank(airdropAgent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AirdropController.TooEarly.selector,
                JOB_B,
                scheduledAt,
                scheduledAt - 1
            )
        );
        controller.executeAirdrop1155(JOB_B, _recipients(2), 1, 1, true);
    }

    function testExecute1155OnTime() public {
        uint256 scheduledAt = T0 + ONE_HOUR;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_B,
            address(nft1155),
            AirdropController.TokenType.ERC1155,
            scheduledAt,
            0
        );

        vm.warp(scheduledAt);

        vm.prank(airdropAgent);
        controller.executeAirdrop1155(JOB_B, _recipients(3), 1, 5, true);

        assertEq(nft1155.balanceOf(_recipients(3)[0], 1), 5);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AirdropScheduler keeper flow
    // ─────────────────────────────────────────────────────────────────────────

    function testSchedulerCheckUpkeepBeforeTime() public {
        uint256 scheduledAt = T0 + ONE_HOUR;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            0
        );

        // Register in scheduler
        bytes32 execId = keccak256("exec-001");
        vm.prank(admin);
        scheduler.scheduleExecution(
            execId,
            JOB_A,
            address(controller),
            _recipients(3),
            1,
            0,
            true
        );

        // Before scheduledAt — checkUpkeep should return false
        vm.warp(scheduledAt - 1);
        (bool needed, ) = scheduler.checkUpkeep("");
        assertFalse(needed, "should not be ready before scheduledAt");
    }

    function testSchedulerCheckUpkeepAfterTime() public {
        uint256 scheduledAt = T0 + ONE_HOUR;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            0
        );

        bytes32 execId = keccak256("exec-001");
        vm.prank(admin);
        scheduler.scheduleExecution(
            execId,
            JOB_A,
            address(controller),
            _recipients(3),
            1,
            0,
            true
        );

        // After scheduledAt — checkUpkeep should return true
        vm.warp(scheduledAt + 1);
        (bool needed, bytes memory performData) = scheduler.checkUpkeep("");
        assertTrue(needed, "should be ready after scheduledAt");

        bytes32 returnedId = abi.decode(performData, (bytes32));
        assertEq(returnedId, execId);
    }

    function testSchedulerPerformUpkeep() public {
        uint256 scheduledAt = T0 + ONE_HOUR;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            0
        );

        address[] memory recipients = _recipients(3);
        bytes32 execId = keccak256("exec-001");

        vm.prank(admin);
        scheduler.scheduleExecution(
            execId,
            JOB_A,
            address(controller),
            recipients,
            1,
            0,
            true
        );

        // Warp to execution time and trigger via performUpkeep
        vm.warp(scheduledAt + 1);

        vm.prank(airdropAgent); // airdropAgent has KEEPER_ROLE
        scheduler.performUpkeep(abi.encode(execId));

        // Verify NFTs landed
        for (uint256 i; i < recipients.length; i++) {
            assertEq(nft721.balanceOf(recipients[i]), 1);
        }

        // Verify job completed
        assertEq(
            uint8(controller.getJobStatus(JOB_A).status),
            uint8(AirdropController.AirdropStatus.Completed)
        );

        // After execution, checkUpkeep should return false for this execId
        (bool needed, ) = scheduler.checkUpkeep("");
        assertFalse(needed, "no more upkeep needed after execution");
    }

    function testSchedulerCannotTriggerTwice() public {
        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            0,
            0
        );

        bytes32 execId = keccak256("exec-001");
        vm.prank(admin);
        scheduler.scheduleExecution(
            execId,
            JOB_A,
            address(controller),
            _recipients(2),
            1,
            0,
            true
        );

        vm.prank(airdropAgent);
        scheduler.triggerExecution(execId);

        // Second trigger must revert
        vm.prank(airdropAgent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AirdropScheduler.AlreadyExecuted.selector,
                execId
            )
        );
        scheduler.triggerExecution(execId);
    }

    function testNonKeeperCannotTrigger() public {
        bytes32 execId = keccak256("exec-001");
        vm.prank(nobody);
        vm.expectRevert();
        scheduler.triggerExecution(execId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Gas benchmarks
    // ─────────────────────────────────────────────────────────────────────────

    function test_gas_CreateScheduledJob() public {
        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            T0 + ONE_HOUR,
            T0 + ONE_DAY
        );
    }

    function test_gas_ExecuteAfterWarp() public {
        uint256 scheduledAt = T0 + ONE_HOUR;

        vm.prank(airdropAgent);
        controller.createJob(
            JOB_A,
            address(nft721),
            AirdropController.TokenType.ERC721,
            scheduledAt,
            0
        );

        vm.warp(scheduledAt);

        vm.prank(airdropAgent);
        controller.executeAirdrop721(JOB_A, _recipients(10), 1, true);
    }
}
