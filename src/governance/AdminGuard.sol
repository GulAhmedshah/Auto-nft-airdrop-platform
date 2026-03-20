// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title  AdminGuard
 * @author NFT Airdrop Platform — P1-I7
 * @notice On-chain multi-signature quorum guard for critical admin operations.
 *
 * ── The Problem It Solves ────────────────────────────────────────────────────
 *
 *   In all previous iterations, a single admin wallet can unilaterally:
 *     • Cancel airdrop jobs           • Pause contracts
 *     • Update Merkle roots           • Deploy new collections
 *
 *   If that wallet is compromised, the entire platform is at risk.
 *
 *   AdminGuard solves this by requiring M-of-N admin signatures before
 *   any critical action executes on-chain. No single wallet can act alone.
 *
 * ── How It Works ─────────────────────────────────────────────────────────────
 *
 *   1. Any PROPOSER_ROLE address calls propose(actionId, targetContract, callData)
 *      This registers the action and emits ActionProposed.
 *
 *   2. Each ADMIN_ROLE address calls approve(actionId) independently.
 *      Each approval emits ActionApproved with actor + timestamp + approvalCount.
 *
 *   3. Once approvalCount >= quorum, anyone calls execute(actionId).
 *      AdminGuard makes a low-level call to targetContract with callData.
 *      Emits ActionExecuted with full audit trail.
 *
 *   4. Executed actions are permanently locked — cannot be re-executed.
 *
 * ── Integration Pattern ───────────────────────────────────────────────────────
 *
 *   STANDALONE MODULE (recommended):
 *     Deploy AdminGuard separately.
 *     Grant AdminGuard the DEFAULT_ADMIN_ROLE on AirdropController,
 *     MerkleAirdrop, NFT721, NFT1155.
 *     All critical calls now route through AdminGuard's quorum check.
 *
 *   This means:
 *     AdminGuard.propose(actionId, address(controller), cancelJobCalldata)
 *     AdminGuard.approve(actionId)  ← called by admin1
 *     AdminGuard.approve(actionId)  ← called by admin2
 *     AdminGuard.execute(actionId)  ← anyone can trigger once quorum reached
 *
 * ── Gnosis Safe Integration Path ─────────────────────────────────────────────
 *
 *   For production, replace this contract with a Gnosis Safe multisig:
 *
 *   1. Deploy a Gnosis Safe with your admin signers at https://app.safe.global
 *   2. Grant DEFAULT_ADMIN_ROLE on all platform contracts to the Safe address
 *   3. Revoke DEFAULT_ADMIN_ROLE from all individual EOA wallets
 *   4. All admin actions now require M-of-N signatures in the Safe UI
 *
 *   The Safe approach is battle-tested with $50B+ in assets secured.
 *   This AdminGuard contract is a lightweight on-chain equivalent suitable
 *   for learning, testnets, and simpler production deployments.
 *
 * ── Roles ───────────────────────────────────────────────────────────────────
 *   DEFAULT_ADMIN_ROLE  – manage admins and quorum setting
 *   ADMIN_ROLE          – approve proposed actions (the "signers")
 *   PROPOSER_ROLE       – propose new actions (can be same as ADMIN_ROLE)
 */
contract AdminGuard is AccessControl {
    // ─────────────────────────────────────────────────────────────────────────
    // Roles
    // ─────────────────────────────────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    // ─────────────────────────────────────────────────────────────────────────
    // Enums
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Lifecycle state of a proposed action.
    enum ActionStatus {
        Pending,
        Executed,
        Cancelled
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice On-chain record of a proposed admin actio
     *
     * @param actionId       Unique identifier (keccak256 of a description off-chain).
     * @param target         Contract address the callData will be sent to.
     * @param callData       ABI-encoded function call to execute.
     * @param proposedBy     Address that proposed this action.
     * @param proposedAt     Block timestamp of the proposal.
     * @param executedAt     Block timestamp of execution (0 if not yet executed).
     * @param approvalCount  Number of unique admin approvals received so far.
     * @param status         Current lifecycle state.
     */
    struct Action {
        bytes32 actionId;
        address target;
        bytes callData;
        address proposedBy;
        uint256 proposedAt;
        uint256 executedAt;
        uint256 approvalCount;
        ActionStatus status;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Required number of admin approvals before an action can execute.
    uint256 public quorum;

    /// @notice All proposed actions keyed by actionId.
    mapping(bytes32 => Action) private _actions;

    /// @notice Per-action approval tracking: actionId → admin → hasApproved.
    mapping(bytes32 => mapping(address => bool)) public approvals;

    // ─────────────────────────────────────────────────────────────────────────
    // Events — immutable audit trail
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Emitted when a new action is proposed.
     * @param actionId   Unique action identifier.
     * @param target     Contract the action will call.
     * @param proposedBy Address that submitted the proposal.
     * @param timestamp  Block timestamp of the proposal.
     */
    event ActionProposed(
        bytes32 indexed actionId,
        address indexed target,
        address indexed proposedBy,
        uint256 timestamp
    );

    /**
     * @notice Emitted when an admin approves an action.
     * @param actionId      The action being approved.
     * @param approvedBy    Admin address granting approval.
     * @param timestamp     Block timestamp of approval.
     * @param approvalCount Running total of unique approvals for this action.
     */
    event ActionApproved(
        bytes32 indexed actionId,
        address indexed approvedBy,
        uint256 timestamp,
        uint256 approvalCount
    );

    /**
     * @notice Emitted when an action is executed after quorum is reached.
     * @param actionId   The executed action.
     * @param executedBy Address that triggered execution.
     * @param target     Contract that was called.
     * @param timestamp  Block timestamp of execution.
     */
    event ActionExecuted(
        bytes32 indexed actionId,
        address indexed executedBy,
        address indexed target,
        uint256 timestamp
    );

    /**
     * @notice Emitted when an admin cancels a pending action.
     * @param actionId    The cancelled action.
     * @param cancelledBy Admin that cancelled.
     * @param timestamp   Block timestamp of cancellation.
     */
    event ActionCancelled(
        bytes32 indexed actionId,
        address indexed cancelledBy,
        uint256 timestamp
    );

    /**
     * @notice Emitted when the quorum threshold is updated.
     * @param oldQuorum Previous quorum value.
     * @param newQuorum New quorum value.
     * @param updatedBy Admin that changed it.
     */
    event QuorumUpdated(
        uint256 oldQuorum,
        uint256 newQuorum,
        address indexed updatedBy
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev No action found for this actionId.
    error ActionNotFound(bytes32 actionId);

    /// @dev Action is not in Pending state — already executed or cancelled.
    error ActionNotPending(bytes32 actionId, ActionStatus status);

    /// @dev actionId already exists.
    error ActionAlreadyExists(bytes32 actionId);

    /// @dev This admin has already approved this action.
    error AlreadyApproved(bytes32 actionId, address admin);

    /// @dev Not enough approvals yet to execute.
    error QuorumNotReached(bytes32 actionId, uint256 current, uint256 required);

    /// @dev The low-level call to the target contract failed.
    error ExecutionFailed(bytes32 actionId, bytes returnData);

    /// @dev New quorum value is invalid (0 or exceeds admin count).
    error InvalidQuorum(uint256 quorum);

    /// @dev Zero address passed where a real address is required.
    error ZeroAddress();

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param superAdmin_  Address granted DEFAULT_ADMIN_ROLE. This address
     *                     manages the admin list and quorum setting.
     * @param admins_      Initial set of ADMIN_ROLE addresses (the "signers").
     *                     Must have at least `quorum_` members.
     * @param quorum_      Number of approvals required (e.g. 2 for a 2-of-3).
     *
     * @dev The superAdmin is also granted ADMIN_ROLE and PROPOSER_ROLE so
     *      the system is immediately usable after deployment.
     */
    constructor(
        address superAdmin_,
        address[] memory admins_,
        uint256 quorum_
    ) {
        if (superAdmin_ == address(0)) revert ZeroAddress();
        require(quorum_ > 0, "AdminGuard: quorum must be > 0");
        require(
            admins_.length >= quorum_,
            "AdminGuard: not enough admins for quorum"
        );

        _grantRole(DEFAULT_ADMIN_ROLE, superAdmin_);
        _grantRole(ADMIN_ROLE, superAdmin_);
        _grantRole(PROPOSER_ROLE, superAdmin_);

        for (uint256 i; i < admins_.length; ) {
            if (admins_[i] == address(0)) revert ZeroAddress();
            _grantRole(ADMIN_ROLE, admins_[i]);
            _grantRole(PROPOSER_ROLE, admins_[i]);
            unchecked {
                ++i;
            }
        }

        quorum = quorum_;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core multi-sig flow
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Propose a new admin action for multi-sig approval.
     * @dev    Restricted to PROPOSER_ROLE.
     *
     * @param actionId  Unique identifier. Use keccak256("cancelJob:0xabc123")
     *                  or any meaningful off-chain string hash.
     * @param target    Contract address to call when executed.
     * @param callData  ABI-encoded function call.
     *                  Example: abi.encodeWithSignature("cancelJob(bytes32)", jobId)
     */
    function propose(
        bytes32 actionId,
        address target,
        bytes calldata callData
    ) external onlyRole(PROPOSER_ROLE) {
        if (actionId == bytes32(0)) revert ZeroAddress();
        if (target == address(0)) revert ZeroAddress();
        if (_actions[actionId].proposedAt != 0)
            revert ActionAlreadyExists(actionId);

        _actions[actionId] = Action({
            actionId: actionId,
            target: target,
            callData: callData,
            proposedBy: msg.sender,
            proposedAt: block.timestamp,
            executedAt: 0,
            approvalCount: 0,
            status: ActionStatus.Pending
        });

        emit ActionProposed(actionId, target, msg.sender, block.timestamp);
    }

    /**
     * @notice Approve a pending action.
     * @dev    Restricted to ADMIN_ROLE. Each admin can only approve once.
     *         Duplicate approvals revert — they do NOT silently pass.
     *
     * @param actionId The action to approve.
     */
    function approve(bytes32 actionId) external onlyRole(ADMIN_ROLE) {
        Action storage action = _requirePendingAction(actionId);

        if (approvals[actionId][msg.sender]) {
            revert AlreadyApproved(actionId, msg.sender);
        }

        approvals[actionId][msg.sender] = true;
        action.approvalCount += 1;

        emit ActionApproved(
            actionId,
            msg.sender,
            block.timestamp,
            action.approvalCount
        );
    }

    /**
     * @notice Execute an action once quorum has been reached.
     * @dev    No role restriction — anyone can trigger execution once quorum
     *         is met. This allows a keeper or relayer to execute without
     *         needing an admin role, reducing operational friction.
     *
     *         The action is marked Executed BEFORE the external call to
     *         prevent reentrancy.
     *
     * @param actionId The action to execute.
     */
    function execute(bytes32 actionId) external {
        Action storage action = _requirePendingAction(actionId);

        if (action.approvalCount < quorum) {
            revert QuorumNotReached(actionId, action.approvalCount, quorum);
        }

        // Mark executed BEFORE external call — reentrancy protection
        action.status = ActionStatus.Executed;
        action.executedAt = block.timestamp;

        emit ActionExecuted(
            actionId,
            msg.sender,
            action.target,
            block.timestamp
        );

        // Execute the call
        (bool success, bytes memory returnData) = action.target.call(
            action.callData
        );
        if (!success) revert ExecutionFailed(actionId, returnData);
    }

    /**
     * @notice Cancel a pending action before it reaches quorum or gets executed.
     * @dev    Restricted to DEFAULT_ADMIN_ROLE (superAdmin only).
     *
     * @param actionId The action to cancel.
     */
    function cancelAction(
        bytes32 actionId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Action storage action = _requirePendingAction(actionId);
        action.status = ActionStatus.Cancelled;

        emit ActionCancelled(actionId, msg.sender, block.timestamp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quorum management
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Update the quorum threshold.
     * @dev    DEFAULT_ADMIN_ROLE only.
     *         New quorum must be > 0. Caller is responsible for ensuring
     *         enough ADMIN_ROLE members exist to meet the new quorum.
     * @param newQuorum New number of required approvals.
     */
    function setQuorum(
        uint256 newQuorum
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newQuorum == 0) revert InvalidQuorum(newQuorum);
        uint256 old = quorum;
        quorum = newQuorum;
        emit QuorumUpdated(old, newQuorum, msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Return the full Action struct for a given actionId.
     * @param actionId The action to look up.
     * @return The Action struct.
     */
    function getAction(bytes32 actionId) external view returns (Action memory) {
        if (_actions[actionId].proposedAt == 0) revert ActionNotFound(actionId);
        return _actions[actionId];
    }

    /**
     * @notice Check how many approvals a given action has received.
     * @param actionId The action to query.
     * @return count Number of unique admin approvals so far.
     */
    function approvalCount(
        bytes32 actionId
    ) external view returns (uint256 count) {
        return _actions[actionId].approvalCount;
    }

    /**
     * @notice Check whether a specific admin has approved a given action.
     * @param actionId The action to check.
     * @param admin    The admin address to check.
     * @return True if that admin has approved.
     */
    function hasApproved(
        bytes32 actionId,
        address admin
    ) external view returns (bool) {
        return approvals[actionId][admin];
    }

    /**
     * @notice Check whether an action has enough approvals to execute.
     * @param actionId The action to check.
     * @return True if approvalCount >= quorum.
     */
    function isReady(bytes32 actionId) external view returns (bool) {
        return _actions[actionId].approvalCount >= quorum;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Retrieves an action, reverts if not found or not Pending.
    function _requirePendingAction(
        bytes32 actionId
    ) internal view returns (Action storage action) {
        action = _actions[actionId];
        if (action.proposedAt == 0) revert ActionNotFound(actionId);
        if (action.status != ActionStatus.Pending) {
            revert ActionNotPending(actionId, action.status);
        }
    }
}
