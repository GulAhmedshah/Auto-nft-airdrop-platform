// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {INFT721}  from "../tokens/INFT721.sol";
import {INFT1155} from "../tokens/INFT1155.sol";

/**
 * @title  AirdropController
 * @author NFT Airdrop Platform — P1-I4 + P1-I6
 * @notice Standalone orchestrator that manages airdrop jobs for both ERC-721
 *         and ERC-1155 token contracts.
 *
 * ── What changed in P1-I6 ───────────────────────────────────────────────────
 *   AirdropJob struct gained two new time fields:
 *     scheduledAt  — earliest block.timestamp at which execution is allowed
 *     expiresAt    — latest block.timestamp at which execution is allowed
 *
 *   createJob() gained two new params: scheduledAt, expiresAt
 *     scheduledAt = 0  → immediate (no time lock)
 *     expiresAt   = 0  → no expiry
 *
 *   Both execute functions now enforce:
 *     block.timestamp >= scheduledAt  (TooEarly)
 *     block.timestamp <= expiresAt    (JobExpired) — only when expiresAt > 0
 *
 *   New functions: cancelJob(), rescheduleJob()
 *   New events:    AirdropScheduled, JobCancelled, JobRescheduled
 *   New errors:    TooEarly, JobExpired, JobNotCancellable, JobNotReschedulable
 *
 * ── Job Lifecycle (extended) ─────────────────────────────────────────────────
 *
 *   Pending ──────────────────────────────► InProgress ──► Completed
 *      │         (execute after scheduledAt,                     ↑
 *      │          before expiresAt)                              │
 *      └──► Failed (via cancelJob or markJobFailed)              │
 *                                                          (isFinalBatch=true)
 *
 * ── Roles ───────────────────────────────────────────────────────────────────
 *   DEFAULT_ADMIN_ROLE  – configure batch size, cancel jobs, mark failed
 *   AIRDROP_ROLE        – create jobs, execute airdrops, reschedule jobs
 */
contract AirdropController is AccessControl {

    // ─────────────────────────────────────────────────────────────────────────
    // Roles
    // ─────────────────────────────────────────────────────────────────────────

    bytes32 public constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");
    bytes32 internal constant TOKEN_AIRDROP_ROLE = keccak256("AIRDROP_ROLE");

    // ─────────────────────────────────────────────────────────────────────────
    // Enums
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Type of token contract the job targets.
    enum TokenType { ERC721, ERC1155 }

    /// @notice Lifecycle state of an airdrop job.
    enum AirdropStatus { Pending, InProgress, Completed, Failed }

    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Full on-chain record of a single airdrop job.
     *
     * @param jobId            Unique identifier supplied by the caller.
     * @param tokenContract    Address of the NFT721 or NFT1155 contract.
     * @param tokenType        ERC721 or ERC1155.
     * @param status           Current lifecycle state.
     * @param totalRecipients  Total recipients processed across all batches.
     * @param processedCount   Recipients processed so far.
     * @param createdAt        Block timestamp when createJob was called.
     * @param executedAt       Block timestamp of the most recent execute call.
     * @param scheduledAt      Earliest timestamp execution is allowed (0 = immediate).
     * @param expiresAt        Latest timestamp execution is allowed (0 = no expiry).
     */
    struct AirdropJob {
        bytes32       jobId;
        address       tokenContract;
        TokenType     tokenType;
        AirdropStatus status;
        uint256       totalRecipients;
        uint256       processedCount;
        uint256       createdAt;
        uint256       executedAt;
        uint256       scheduledAt;   // ← NEW in P1-I6
        uint256       expiresAt;     // ← NEW in P1-I6
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    mapping(bytes32 => AirdropJob) private _jobs;
    uint256 public maxBatchSize;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event JobCreated(
        bytes32 indexed jobId,
        address indexed tokenContract,
        TokenType tokenType
    );

    /**
     * @notice Emitted when a job is created with time constraints.
     * @param jobId        The job identifier.
     * @param scheduledAt  Earliest execution timestamp.
     * @param expiresAt    Latest execution timestamp (0 = no expiry).
     */
    event AirdropScheduled(
        bytes32 indexed jobId,
        uint256 scheduledAt,
        uint256 expiresAt
    );

    event AirdropExecuted(
        bytes32 indexed jobId,
        uint256 batchSize,
        uint256 gasUsed
    );

    event JobCompleted(bytes32 indexed jobId, uint256 totalRecipients);

    event JobFailed(bytes32 indexed jobId);

    /**
     * @notice Emitted when an admin explicitly cancels a pending job.
     * @param jobId      The cancelled job.
     * @param cancelledBy Address that triggered the cancellation.
     */
    event JobCancelled(bytes32 indexed jobId, address indexed cancelledBy);

    /**
     * @notice Emitted when a pending job's scheduled time is updated.
     * @param jobId          The rescheduled job.
     * @param oldScheduledAt Previous scheduled timestamp.
     * @param newScheduledAt New scheduled timestamp.
     */
    event JobRescheduled(
        bytes32 indexed jobId,
        uint256 oldScheduledAt,
        uint256 newScheduledAt
    );

    event MaxBatchSizeUpdated(uint256 oldSize, uint256 newSize);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error JobAlreadyExists(bytes32 jobId);
    error JobNotFound(bytes32 jobId);
    error JobNotExecutable(bytes32 jobId, AirdropStatus status);
    error BatchTooLarge(uint256 requested, uint256 maxAllowed);
    error ControllerNotAuthorized(address tokenContract);
    error TokenTypeMismatch(bytes32 jobId, TokenType expected, TokenType got);
    error ZeroRecipients();
    error ZeroAddress();

    /// @dev Execution attempted before scheduledAt has been reached.
    error TooEarly(bytes32 jobId, uint256 scheduledAt, uint256 currentTime);

    /// @dev Execution attempted after expiresAt has passed.
    error JobExpired(bytes32 jobId, uint256 expiresAt, uint256 currentTime);

    /// @dev cancelJob called on a job that is already Completed or Failed.
    error JobNotCancellable(bytes32 jobId, AirdropStatus status);

    /// @dev rescheduleJob called on a job that is not Pending.
    error JobNotReschedulable(bytes32 jobId, AirdropStatus status);

    /// @dev New scheduledAt is in the past.
    error ScheduledAtInPast(uint256 scheduledAt, uint256 currentTime);

    /// @dev expiresAt is set but is not after scheduledAt.
    error InvalidExpiryTime(uint256 scheduledAt, uint256 expiresAt);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address admin_, uint256 maxBatchSize_) {
        if (admin_ == address(0)) revert ZeroAddress();
        require(maxBatchSize_ > 0, "AirdropController: batch size must be > 0");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(AIRDROP_ROLE,       admin_);

        maxBatchSize = maxBatchSize_;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Job management
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Register a new airdrop job with optional time constraints.
     * @dev    Restricted to AIRDROP_ROLE.
     *
     * @param jobId          Unique job identifier.
     * @param tokenContract  NFT contract address.
     * @param tokenType      ERC721 or ERC1155.
     * @param scheduledAt    Earliest execution timestamp. Pass 0 for immediate.
     * @param expiresAt      Latest execution timestamp. Pass 0 for no expiry.
     */
    function createJob(
        bytes32   jobId,
        address   tokenContract,
        TokenType tokenType,
        uint256   scheduledAt,
        uint256   expiresAt
    )
        external
        onlyRole(AIRDROP_ROLE)
    {
        if (jobId == bytes32(0))         revert ZeroAddress();
        if (tokenContract == address(0)) revert ZeroAddress();
        if (_jobs[jobId].createdAt != 0) revert JobAlreadyExists(jobId);

        // Validate time constraints
        // scheduledAt can be 0 (immediate) or any future timestamp
        if (expiresAt != 0) {
            uint256 effectiveStart = scheduledAt == 0 ? block.timestamp : scheduledAt;
            if (expiresAt <= effectiveStart) {
                revert InvalidExpiryTime(scheduledAt, expiresAt);
            }
        }

        _jobs[jobId] = AirdropJob({
            jobId:           jobId,
            tokenContract:   tokenContract,
            tokenType:       tokenType,
            status:          AirdropStatus.Pending,
            totalRecipients: 0,
            processedCount:  0,
            createdAt:       block.timestamp,
            executedAt:      0,
            scheduledAt:     scheduledAt,
            expiresAt:       expiresAt
        });

        emit JobCreated(jobId, tokenContract, tokenType);

        // Only emit AirdropScheduled when there is a meaningful time constraint
        if (scheduledAt > 0 || expiresAt > 0) {
            emit AirdropScheduled(jobId, scheduledAt, expiresAt);
        }
    }

    /**
     * @notice Cancel a Pending or InProgress job.
     * @dev    Admin only. Sets status to Failed so it can never be executed.
     *         Cannot cancel a job that is already Completed or Failed.
     * @param jobId The job to cancel.
     */
    function cancelJob(bytes32 jobId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        AirdropJob storage job = _requireJob(jobId);

        if (
            job.status == AirdropStatus.Completed ||
            job.status == AirdropStatus.Failed
        ) {
            revert JobNotCancellable(jobId, job.status);
        }

        job.status = AirdropStatus.Failed;
        emit JobCancelled(jobId, msg.sender);
    }

    /**
     * @notice Reschedule a Pending job to a new execution time.
     * @dev    Restricted to AIRDROP_ROLE. Only Pending jobs can be rescheduled.
     *         Once execution has started (InProgress) the time cannot change.
     * @param jobId          The job to reschedule.
     * @param newScheduledAt New earliest execution timestamp (must be in future).
     */
    function rescheduleJob(bytes32 jobId, uint256 newScheduledAt)
        external
        onlyRole(AIRDROP_ROLE)
    {
        AirdropJob storage job = _requireJob(jobId);

        if (job.status != AirdropStatus.Pending) {
            revert JobNotReschedulable(jobId, job.status);
        }

        if (newScheduledAt != 0 && newScheduledAt <= block.timestamp) {
            revert ScheduledAtInPast(newScheduledAt, block.timestamp);
        }

        // Re-validate expiry against new scheduled time
        if (job.expiresAt != 0) {
            uint256 effectiveStart = newScheduledAt == 0
                ? block.timestamp
                : newScheduledAt;
            if (job.expiresAt <= effectiveStart) {
                revert InvalidExpiryTime(newScheduledAt, job.expiresAt);
            }
        }

        uint256 oldScheduledAt = job.scheduledAt;
        job.scheduledAt = newScheduledAt;

        emit JobRescheduled(jobId, oldScheduledAt, newScheduledAt);
    }

    /**
     * @notice Mark an existing job as Failed (emergency escape hatch).
     * @dev    Admin only.
     */
    function markJobFailed(bytes32 jobId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        AirdropJob storage job = _requireJob(jobId);
        job.status = AirdropStatus.Failed;
        emit JobFailed(jobId);
    }

    /**
     * @notice Update the maximum recipients per execute call.
     */
    function setMaxBatchSize(uint256 newSize)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newSize > 0, "AirdropController: must be > 0");
        emit MaxBatchSizeUpdated(maxBatchSize, newSize);
        maxBatchSize = newSize;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Execution — ERC-721
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Execute one batch of an ERC-721 airdrop job.
     * @dev    Enforces scheduledAt and expiresAt time constraints.
     *
     * @param jobId        The job to execute.
     * @param recipients   Recipient addresses for this batch.
     * @param quantity     Tokens each recipient receives.
     * @param isFinalBatch True if this is the last batch.
     */
    function executeAirdrop721(
        bytes32           jobId,
        address[] calldata recipients,
        uint256           quantity,
        bool              isFinalBatch
    )
        external
        onlyRole(AIRDROP_ROLE)
    {
        uint256 gasStart = gasleft();

        AirdropJob storage job = _requireExecutableJob(jobId, TokenType.ERC721);
        _enforceTimeWindow(job);
        _validateBatch(recipients.length);
        _requireControllerAuthorized(job.tokenContract);

        uint256 batchSize = recipients.length;
        uint256[] memory quantities = new uint256[](batchSize);
        for (uint256 i; i < batchSize; ) {
            quantities[i] = quantity;
            unchecked { ++i; }
        }

        INFT721(job.tokenContract).batchMint(recipients, quantities);

        job.status           = AirdropStatus.InProgress;
        job.processedCount  += batchSize;
        job.totalRecipients += batchSize;
        job.executedAt       = block.timestamp;

        if (isFinalBatch) {
            job.status = AirdropStatus.Completed;
            emit JobCompleted(jobId, job.totalRecipients);
        }

        emit AirdropExecuted(jobId, batchSize, gasStart - gasleft());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Execution — ERC-1155
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Execute one batch of an ERC-1155 airdrop job.
     * @dev    Enforces scheduledAt and expiresAt time constraints.
     *
     * @param jobId        The job to execute.
     * @param recipients   Recipient addresses.
     * @param tokenId      ERC-1155 token ID to distribute.
     * @param amountEach   Amount each recipient receives.
     * @param isFinalBatch True if this is the last batch.
     */
    function executeAirdrop1155(
        bytes32           jobId,
        address[] calldata recipients,
        uint256           tokenId,
        uint256           amountEach,
        bool              isFinalBatch
    )
        external
        onlyRole(AIRDROP_ROLE)
    {
        uint256 gasStart = gasleft();

        AirdropJob storage job = _requireExecutableJob(jobId, TokenType.ERC1155);
        _enforceTimeWindow(job);
        _validateBatch(recipients.length);
        _requireControllerAuthorized(job.tokenContract);

        uint256 batchSize = recipients.length;

        INFT1155(job.tokenContract).airdropBatch(recipients, tokenId, amountEach);

        job.status           = AirdropStatus.InProgress;
        job.processedCount  += batchSize;
        job.totalRecipients += batchSize;
        job.executedAt       = block.timestamp;

        if (isFinalBatch) {
            job.status = AirdropStatus.Completed;
            emit JobCompleted(jobId, job.totalRecipients);
        }

        emit AirdropExecuted(jobId, batchSize, gasStart - gasleft());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    function getJobStatus(bytes32 jobId)
        external
        view
        returns (AirdropJob memory)
    {
        if (_jobs[jobId].createdAt == 0) revert JobNotFound(jobId);
        return _jobs[jobId];
    }

    function isAuthorizedOn(address tokenContract) external view returns (bool) {
        return INFT721(tokenContract).hasRole(TOKEN_AIRDROP_ROLE, address(this));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _requireJob(bytes32 jobId)
        internal
        view
        returns (AirdropJob storage job)
    {
        job = _jobs[jobId];
        if (job.createdAt == 0) revert JobNotFound(jobId);
    }

    function _requireExecutableJob(bytes32 jobId, TokenType expectedType)
        internal
        view
        returns (AirdropJob storage job)
    {
        job = _requireJob(jobId);

        if (job.tokenType != expectedType) {
            revert TokenTypeMismatch(jobId, job.tokenType, expectedType);
        }
        if (
            job.status == AirdropStatus.Completed ||
            job.status == AirdropStatus.Failed
        ) {
            revert JobNotExecutable(jobId, job.status);
        }
    }

    /**
     * @dev Enforce both the scheduledAt (lower bound) and expiresAt (upper bound).
     *
     *      scheduledAt == 0  → no lower bound, execute any time
     *      expiresAt   == 0  → no upper bound, never expires
     *
     *      These checks use block.timestamp which miners can influence slightly
     *      (~15 seconds). For airdrop scheduling this is acceptable — we are not
     *      dealing with financial instruments where miner manipulation matters.
     */
    function _enforceTimeWindow(AirdropJob storage job) internal view {
        // Lower bound: not before scheduledAt
        if (job.scheduledAt != 0 && block.timestamp < job.scheduledAt) {
            revert TooEarly(job.jobId, job.scheduledAt, block.timestamp);
        }

        // Upper bound: not after expiresAt
        if (job.expiresAt != 0 && block.timestamp > job.expiresAt) {
            revert JobExpired(job.jobId, job.expiresAt, block.timestamp);
        }
    }

    function _validateBatch(uint256 batchSize) internal view {
        if (batchSize == 0) revert ZeroRecipients();
        if (batchSize > maxBatchSize) {
            revert BatchTooLarge(batchSize, maxBatchSize);
        }
    }

    function _requireControllerAuthorized(address tokenContract) internal view {
        if (!INFT721(tokenContract).hasRole(TOKEN_AIRDROP_ROLE, address(this))) {
            revert ControllerNotAuthorized(tokenContract);
        }
    }
}
