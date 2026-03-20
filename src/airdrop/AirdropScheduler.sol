// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// IController lives at FILE LEVEL — interfaces cannot be inside a contract.
interface IController {
    enum TokenType     { ERC721, ERC1155 }
    enum AirdropStatus { Pending, InProgress, Completed, Failed }

    struct AirdropJob {
        bytes32       jobId;
        address       tokenContract;
        TokenType     tokenType;
        AirdropStatus status;
        uint256       totalRecipients;
        uint256       processedCount;
        uint256       createdAt;
        uint256       executedAt;
        uint256       scheduledAt;
        uint256       expiresAt;
    }

    function executeAirdrop721(
        bytes32            jobId,
        address[] calldata recipients,
        uint256            quantity,
        bool               isFinalBatch
    ) external;

    function executeAirdrop1155(
        bytes32            jobId,
        address[] calldata recipients,
        uint256            tokenId,
        uint256            amountEach,
        bool               isFinalBatch
    ) external;

    function getJobStatus(bytes32 jobId) external view returns (AirdropJob memory);
}

/**
 * @title  AirdropScheduler
 * @author NFT Airdrop Platform — P1-I6
 * @notice Bridges a keeper (Chainlink Automation / Gelato / cron) with
 *         the AirdropController. Chainlink calls checkUpkeep() every block
 *         and performUpkeep() when a job is ready to execute.
 *
 * Roles
 *   DEFAULT_ADMIN_ROLE – register/remove scheduled executions
 *   KEEPER_ROLE        – trigger executions (grant to keeper bot address)
 */
contract AirdropScheduler is AccessControl {

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    struct ScheduledExecution {
        bytes32   jobId;
        address   controller;
        address[] recipients;
        uint256   quantity;
        uint256   tokenId;
        bool      isFinalBatch;
        bool      executed;
    }

    mapping(bytes32 => ScheduledExecution) public schedules;
    bytes32[] public executionIds;

    event ExecutionScheduled(bytes32 indexed executionId, bytes32 indexed jobId, address indexed controller);
    event ExecutionTriggered(bytes32 indexed executionId, bytes32 indexed jobId, address indexed triggeredBy);
    event ExecutionRemoved(bytes32 indexed executionId);

    error ExecutionNotFound(bytes32 executionId);
    error AlreadyExecuted(bytes32 executionId);
    error ZeroAddress();

    constructor(address admin_) {
        if (admin_ == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(KEEPER_ROLE, admin_);
    }

    function scheduleExecution(
        bytes32            executionId,
        bytes32            jobId,
        address            controller,
        address[] calldata recipients,
        uint256            quantity,
        uint256            tokenId,
        bool               isFinalBatch
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (controller == address(0)) revert ZeroAddress();
        require(schedules[executionId].controller == address(0), "AirdropScheduler: exists");

        schedules[executionId] = ScheduledExecution({
            jobId:        jobId,
            controller:   controller,
            recipients:   recipients,
            quantity:     quantity,
            tokenId:      tokenId,
            isFinalBatch: isFinalBatch,
            executed:     false
        });

        executionIds.push(executionId);
        emit ExecutionScheduled(executionId, jobId, controller);
    }

    function removeExecution(bytes32 executionId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ScheduledExecution storage exec = _requireExecution(executionId);
        if (exec.executed) revert AlreadyExecuted(executionId);
        delete schedules[executionId];
        emit ExecutionRemoved(executionId);
    }

    function checkUpkeep(bytes calldata)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        for (uint256 i; i < executionIds.length; ) {
            bytes32 execId = executionIds[i];
            ScheduledExecution storage exec = schedules[execId];

            if (!exec.executed && exec.controller != address(0)) {
                try IController(exec.controller).getJobStatus(exec.jobId)
                    returns (IController.AirdropJob memory job)
                {
                    bool withinWindow = (
                        job.scheduledAt == 0 || block.timestamp >= job.scheduledAt
                    ) && (
                        job.expiresAt == 0 || block.timestamp <= job.expiresAt
                    );
                    bool executable = (
                        job.status == IController.AirdropStatus.Pending ||
                        job.status == IController.AirdropStatus.InProgress
                    );
                    if (withinWindow && executable) {
                        return (true, abi.encode(execId));
                    }
                } catch {}
            }
            unchecked { ++i; }
        }
        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external onlyRole(KEEPER_ROLE) {
        bytes32 executionId = abi.decode(performData, (bytes32));
        triggerExecution(executionId);
    }

    function triggerExecution(bytes32 executionId) public onlyRole(KEEPER_ROLE) {
        ScheduledExecution storage exec = _requireExecution(executionId);
        if (exec.executed) revert AlreadyExecuted(executionId);

        exec.executed = true;

        IController.AirdropJob memory job = IController(exec.controller).getJobStatus(exec.jobId);

        if (job.tokenType == IController.TokenType.ERC721) {
            IController(exec.controller).executeAirdrop721(
                exec.jobId, exec.recipients, exec.quantity, exec.isFinalBatch
            );
        } else {
            IController(exec.controller).executeAirdrop1155(
                exec.jobId, exec.recipients, exec.tokenId, exec.quantity, exec.isFinalBatch
            );
        }

        emit ExecutionTriggered(executionId, exec.jobId, msg.sender);
    }

    function executionCount() external view returns (uint256) {
        return executionIds.length;
    }

    function _requireExecution(bytes32 executionId)
        internal
        view
        returns (ScheduledExecution storage exec)
    {
        exec = schedules[executionId];
        if (exec.controller == address(0)) revert ExecutionNotFound(executionId);
    }
}
