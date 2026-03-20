// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2}     from "forge-std/Test.sol";
import {AdminGuard}         from "../src/governance/AdminGuard.sol";
import {AirdropController}  from "../src/airdrop/AirdropController.sol";
import {NFT721}             from "../src/tokens/NFT721.sol";

/**
 * @title  AdminGuardTest
 * @notice Foundry tests for AdminGuard — covers every P1-I7 acceptance criterion.
 *
 * Run:
 *   forge test --match-contract AdminGuardTest -vv
 */
contract AdminGuardTest is Test {

    // ── Contracts ────────────────────────────────────────────────────────────
    AdminGuard        internal guard;
    AirdropController internal controller;
    NFT721            internal nft;

    // ── Actors ───────────────────────────────────────────────────────────────
    address internal superAdmin = makeAddr("superAdmin");
    address internal admin1     = makeAddr("admin1");
    address internal admin2     = makeAddr("admin2");
    address internal admin3     = makeAddr("admin3");
    address internal nobody     = makeAddr("nobody");
    address internal keeper     = makeAddr("keeper"); // can execute once quorum met

    // ── Role constants ────────────────────────────────────────────────────────
    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 constant ADMIN_ROLE         = keccak256("ADMIN_ROLE");
    bytes32 constant PROPOSER_ROLE      = keccak256("PROPOSER_ROLE");
    bytes32 constant AIRDROP_ROLE       = keccak256("AIRDROP_ROLE");

    // ── Reusable action IDs ───────────────────────────────────────────────────
    bytes32 constant ACTION_A = keccak256("action-alpha");
    bytes32 constant ACTION_B = keccak256("action-beta");
    bytes32 constant ACTION_C = keccak256("action-gamma");

    // ─────────────────────────────────────────────────────────────────────────
    // Setup
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        // Build 3 admin signers
        address[] memory admins = new address[](3);
        admins[0] = admin1;
        admins[1] = admin2;
        admins[2] = admin3;

        // Deploy AdminGuard with 2-of-3 quorum
        guard = new AdminGuard(superAdmin, admins, 2);

        // Deploy NFT721 and AirdropController for integration tests
        // Both start with superAdmin as admin
        nft        = new NFT721("Guard Test NFT", "GNFT", "ipfs://x/", 0, superAdmin);
        controller = new AirdropController(superAdmin, 500);

        // Wire: grant DEFAULT_ADMIN_ROLE on NFT and Controller TO AdminGuard
        vm.startPrank(superAdmin);
        nft.grantRole(DEFAULT_ADMIN_ROLE,        address(guard));
        controller.grantRole(DEFAULT_ADMIN_ROLE, address(guard));

        // Grant AIRDROP_ROLE on NFT to controller (needed for integration test)
        nft.grantRole(AIRDROP_ROLE, address(controller));
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Deployment sanity
    // ─────────────────────────────────────────────────────────────────────────

    function test_DeploymentState() public view {
        assertEq(guard.quorum(), 2);
        assertTrue(guard.hasRole(DEFAULT_ADMIN_ROLE, superAdmin));
        assertTrue(guard.hasRole(ADMIN_ROLE,         superAdmin));
        assertTrue(guard.hasRole(ADMIN_ROLE,         admin1));
        assertTrue(guard.hasRole(ADMIN_ROLE,         admin2));
        assertTrue(guard.hasRole(ADMIN_ROLE,         admin3));
        assertFalse(guard.hasRole(ADMIN_ROLE,        nobody));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // propose()
    // ─────────────────────────────────────────────────────────────────────────

    function testPropose() public {
        bytes memory callData = abi.encodeWithSignature("pause()");

        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), callData);

        AdminGuard.Action memory action = guard.getAction(ACTION_A);
        assertEq(action.actionId,      ACTION_A);
        assertEq(action.target,        address(nft));
        assertEq(action.callData,      callData);
        assertEq(action.proposedBy,    admin1);
        assertEq(action.approvalCount, 0);
        assertEq(uint8(action.status), uint8(AdminGuard.ActionStatus.Pending));
        assertGt(action.proposedAt,    0);
    }

    function testProposeEmitsEvent() public {
        bytes memory callData = abi.encodeWithSignature("pause()");

        vm.expectEmit(true, true, true, true, address(guard));
        emit AdminGuard.ActionProposed(ACTION_A, address(nft), admin1, block.timestamp);

        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), callData);
    }

    function testNonProposerCannotPropose() public {
        vm.prank(nobody);
        vm.expectRevert();
        guard.propose(ACTION_A, address(nft), "");
    }

    function testDuplicateActionIdReverts() public {
        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), "");

        vm.prank(admin2);
        vm.expectRevert(
            abi.encodeWithSelector(AdminGuard.ActionAlreadyExists.selector, ACTION_A)
        );
        guard.propose(ACTION_A, address(nft), "");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testSingleAdminBelowQuorum — one approval on 2-of-3, expect NotReady revert
    // ─────────────────────────────────────────────────────────────────────────

    function testSingleAdminBelowQuorum() public {
        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), "");

        // Only one approval — quorum is 2
        vm.prank(admin1);
        guard.approve(ACTION_A);

        // Execute should revert — quorum not reached
        vm.expectRevert(
            abi.encodeWithSelector(
                AdminGuard.QuorumNotReached.selector,
                ACTION_A, 1, 2
            )
        );
        guard.execute(ACTION_A);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testQuorumReached — 2 admins approve, execute succeeds
    // ─────────────────────────────────────────────────────────────────────────

    function testQuorumReached() public {
        // Propose: pause the NFT contract
        bytes memory callData = abi.encodeWithSignature("pause()");

        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), callData);

        // Admin1 approves
        vm.prank(admin1);
        guard.approve(ACTION_A);

        assertFalse(guard.isReady(ACTION_A)); // only 1 of 2 needed

        // Admin2 approves — quorum reached
        vm.prank(admin2);
        guard.approve(ACTION_A);

        assertTrue(guard.isReady(ACTION_A));

        // Anyone can now execute (using keeper here)
        guard.execute(ACTION_A);

        // Verify the call actually executed — NFT should be paused
        assertTrue(nft.paused());

        // Verify action state
        AdminGuard.Action memory action = guard.getAction(ACTION_A);
        assertEq(uint8(action.status), uint8(AdminGuard.ActionStatus.Executed));
        assertGt(action.executedAt, 0);
    }

    function testExecuteEmitsEvent() public {
        bytes memory callData = abi.encodeWithSignature("pause()");

        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), callData);

        vm.prank(admin1);
        guard.approve(ACTION_A);

        vm.prank(admin2);
        guard.approve(ACTION_A);

        vm.expectEmit(true, true, true, true, address(guard));
        emit AdminGuard.ActionExecuted(ACTION_A, address(this), address(nft), block.timestamp);

        guard.execute(ACTION_A);
    }

    function testCannotExecuteTwice() public {
        bytes memory callData = abi.encodeWithSignature("pause()");

        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), callData);

        vm.prank(admin1); guard.approve(ACTION_A);
        vm.prank(admin2); guard.approve(ACTION_A);
        guard.execute(ACTION_A);

        // Second execute must revert — action is no longer Pending
        vm.expectRevert(
            abi.encodeWithSelector(
                AdminGuard.ActionNotPending.selector,
                ACTION_A,
                AdminGuard.ActionStatus.Executed
            )
        );
        guard.execute(ACTION_A);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testDuplicateApproval — same admin approves twice, only counts once
    // ─────────────────────────────────────────────────────────────────────────

    function testDuplicateApproval() public {
        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), "");

        vm.prank(admin1);
        guard.approve(ACTION_A);

        assertEq(guard.approvalCount(ACTION_A), 1);

        // Second approval from same admin must revert
        vm.prank(admin1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AdminGuard.AlreadyApproved.selector,
                ACTION_A, admin1
            )
        );
        guard.approve(ACTION_A);

        // Count should still be 1
        assertEq(guard.approvalCount(ACTION_A), 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testUnknownActionId — approve unknown id reverts
    // ─────────────────────────────────────────────────────────────────────────

    function testUnknownActionId() public {
        bytes32 unknownId = keccak256("does-not-exist");

        vm.prank(admin1);
        vm.expectRevert(
            abi.encodeWithSelector(AdminGuard.ActionNotFound.selector, unknownId)
        );
        guard.approve(unknownId);
    }

    function testGetUnknownActionReverts() public {
        bytes32 unknownId = keccak256("ghost");
        vm.expectRevert(
            abi.encodeWithSelector(AdminGuard.ActionNotFound.selector, unknownId)
        );
        guard.getAction(unknownId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testAuditEvent — all 4 event fields emitted correctly
    // ─────────────────────────────────────────────────────────────────────────

    function testAuditEvent() public {
        uint256 expectedTimestamp = block.timestamp;
        bytes memory callData = abi.encodeWithSignature("pause()");

        // ── ActionProposed event ──────────────────────────────────────────────
        vm.expectEmit(true, true, true, true, address(guard));
        emit AdminGuard.ActionProposed(ACTION_A, address(nft), admin1, expectedTimestamp);

        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), callData);

        // ── ActionApproved event — check all 4 fields ─────────────────────────
        // field1: actionId (indexed)
        // field2: approvedBy (indexed)
        // field3: timestamp
        // field4: approvalCount
        vm.expectEmit(true, true, false, true, address(guard));
        emit AdminGuard.ActionApproved(ACTION_A, admin1, expectedTimestamp, 1);

        vm.prank(admin1);
        guard.approve(ACTION_A);

        vm.expectEmit(true, true, false, true, address(guard));
        emit AdminGuard.ActionApproved(ACTION_A, admin2, expectedTimestamp, 2);

        vm.prank(admin2);
        guard.approve(ACTION_A);

        // ── ActionExecuted event ──────────────────────────────────────────────
        vm.expectEmit(true, true, true, true, address(guard));
        emit AdminGuard.ActionExecuted(ACTION_A, address(this), address(nft), expectedTimestamp);

        guard.execute(ACTION_A);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testSetQuorum — admin updates quorum, old threshold no longer valid
    // ─────────────────────────────────────────────────────────────────────────

    function testSetQuorum() public {
        // Propose with old quorum (2)
        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), "");

        vm.prank(admin1); guard.approve(ACTION_A);
        vm.prank(admin2); guard.approve(ACTION_A);

        assertTrue(guard.isReady(ACTION_A)); // 2 approvals meets quorum=2

        // Raise quorum to 3
        vm.prank(superAdmin);
        guard.setQuorum(3);

        assertEq(guard.quorum(), 3);

        // Same action now needs 3 approvals — execute should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                AdminGuard.QuorumNotReached.selector,
                ACTION_A, 2, 3
            )
        );
        guard.execute(ACTION_A);

        // Third admin approves — now meets new quorum
        vm.prank(admin3);
        guard.approve(ACTION_A);

        // Execute with empty callData succeeds (nft.pause needs admin — skip for this test)
        // Just verify no revert on the quorum check itself
        assertEq(guard.approvalCount(ACTION_A), 3);
        assertTrue(guard.isReady(ACTION_A));
    }

    function testSetQuorumEmitsEvent() public {
        vm.expectEmit(false, false, true, true, address(guard));
        emit AdminGuard.QuorumUpdated(2, 3, superAdmin);

        vm.prank(superAdmin);
        guard.setQuorum(3);
    }

    function testSetQuorumZeroReverts() public {
        vm.prank(superAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(AdminGuard.InvalidQuorum.selector, 0)
        );
        guard.setQuorum(0);
    }

    function testNonAdminCannotSetQuorum() public {
        vm.prank(nobody);
        vm.expectRevert();
        guard.setQuorum(1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // cancelAction
    // ─────────────────────────────────────────────────────────────────────────

    function testCancelAction() public {
        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), "");

        vm.prank(admin1); guard.approve(ACTION_A);

        vm.prank(superAdmin);
        guard.cancelAction(ACTION_A);

        AdminGuard.Action memory action = guard.getAction(ACTION_A);
        assertEq(uint8(action.status), uint8(AdminGuard.ActionStatus.Cancelled));

        // Cannot approve cancelled action
        vm.prank(admin2);
        vm.expectRevert(
            abi.encodeWithSelector(
                AdminGuard.ActionNotPending.selector,
                ACTION_A,
                AdminGuard.ActionStatus.Cancelled
            )
        );
        guard.approve(ACTION_A);

        // Cannot execute cancelled action
        vm.expectRevert(
            abi.encodeWithSelector(
                AdminGuard.ActionNotPending.selector,
                ACTION_A,
                AdminGuard.ActionStatus.Cancelled
            )
        );
        guard.execute(ACTION_A);
    }

    function testNonAdminCannotCancel() public {
        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), "");

        vm.prank(nobody);
        vm.expectRevert();
        guard.cancelAction(ACTION_A);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hasApproved view
    // ─────────────────────────────────────────────────────────────────────────

    function testHasApproved() public {
        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), "");

        assertFalse(guard.hasApproved(ACTION_A, admin1));

        vm.prank(admin1);
        guard.approve(ACTION_A);

        assertTrue(guard.hasApproved(ACTION_A, admin1));
        assertFalse(guard.hasApproved(ACTION_A, admin2));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INTEGRATION — full multi-sig flow on AirdropController
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Full integration: AdminGuard executes cancelJob on AirdropController.
     *
     * Flow:
     *   1. Create a controller job (using superAdmin who still has AIRDROP_ROLE)
     *   2. Propose cancelJob through AdminGuard
     *   3. Two admins approve
     *   4. Execute — AdminGuard calls controller.cancelJob(jobId)
     *   5. Verify job is Failed
     */
    function test_Integration_MultiSigCancelJob() public {
        bytes32 jobId = keccak256("integration-job-001");

        // Create the job (superAdmin has AIRDROP_ROLE on controller)
        vm.prank(superAdmin);
        controller.createJob(
            jobId,
            address(nft),
            AirdropController.TokenType.ERC721,
            0, 0
        );

        // Verify job is Pending
        assertEq(
            uint8(controller.getJobStatus(jobId).status),
            uint8(AirdropController.AirdropStatus.Pending)
        );

        // Propose: cancelJob via AdminGuard
        bytes memory callData = abi.encodeWithSignature(
            "cancelJob(bytes32)", jobId
        );

        vm.prank(admin1);
        guard.propose(ACTION_A, address(controller), callData);

        // Admin1 approves
        vm.prank(admin1);
        guard.approve(ACTION_A);

        // Admin2 approves — quorum reached
        vm.prank(admin2);
        guard.approve(ACTION_A);

        // Execute — AdminGuard calls controller.cancelJob(jobId)
        guard.execute(ACTION_A);

        // Verify job is now Failed (cancelled)
        assertEq(
            uint8(controller.getJobStatus(jobId).status),
            uint8(AirdropController.AirdropStatus.Failed)
        );

        console2.log("Integration test passed: multi-sig cancel job successful.");
    }

    /**
     * @notice Integration: AdminGuard executes pause on NFT721.
     */
    function test_Integration_MultiSigPauseNFT() public {
        assertFalse(nft.paused());

        bytes memory callData = abi.encodeWithSignature("pause()");

        vm.prank(admin1);
        guard.propose(ACTION_B, address(nft), callData);

        vm.prank(admin1); guard.approve(ACTION_B);
        vm.prank(admin3); guard.approve(ACTION_B); // admin3 approves instead of admin2

        guard.execute(ACTION_B);

        assertTrue(nft.paused(), "NFT should be paused after multi-sig execution");
    }

    /**
     * @notice Integration: AdminGuard executes unpause after pause.
     */
    function test_Integration_MultiSigPauseThenUnpause() public {
        // Pause
        bytes memory pauseData = abi.encodeWithSignature("pause()");
        vm.prank(admin1); guard.propose(ACTION_A, address(nft), pauseData);
        vm.prank(admin1); guard.approve(ACTION_A);
        vm.prank(admin2); guard.approve(ACTION_A);
        guard.execute(ACTION_A);
        assertTrue(nft.paused());

        // Unpause via a second action
        bytes memory unpauseData = abi.encodeWithSignature("unpause()");
        vm.prank(admin1); guard.propose(ACTION_B, address(nft), unpauseData);
        vm.prank(admin2); guard.approve(ACTION_B);
        vm.prank(admin3); guard.approve(ACTION_B);
        guard.execute(ACTION_B);
        assertFalse(nft.paused());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Execution failure propagates
    // ─────────────────────────────────────────────────────────────────────────

    function testExecutionFailurePropagates() public {
        // Propose a call with invalid calldata — target will reject it
        bytes memory badCallData = abi.encodeWithSignature("nonExistentFunction()");

        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), badCallData);

        vm.prank(admin1); guard.approve(ACTION_A);
        vm.prank(admin2); guard.approve(ACTION_A);

        // Execute should revert with ExecutionFailed
        vm.expectRevert();
        guard.execute(ACTION_A);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Gas benchmarks
    // ─────────────────────────────────────────────────────────────────────────

    function test_gas_ProposeApproveExecute() public {
        bytes memory callData = abi.encodeWithSignature("pause()");

        vm.prank(admin1);
        guard.propose(ACTION_A, address(nft), callData);

        vm.prank(admin1); guard.approve(ACTION_A);
        vm.prank(admin2); guard.approve(ACTION_A);

        guard.execute(ACTION_A);
    }
}
