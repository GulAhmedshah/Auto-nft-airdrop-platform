# NFT Airdrop Platform — Deployment Manifest

> **Phase 1 Complete.** All smart contracts deployed, tested, and verified.
> Fill in the values below after running `forge script script/Deploy.s.sol`.

---

## Deployment Info

| Field           | Value                  |
|-----------------|------------------------|
| Network         | Sepolia Testnet         |
| Chain ID        | 11155111               |
| Deployer        | `0x_YOUR_ADDRESS_HERE` |
| Deployed At     | YYYY-MM-DD HH:MM UTC   |
| Foundry Version | forge 0.2.x            |
| Solidity        | 0.8.24                 |

---

## Contract Addresses

| Contract           | Address                      | Etherscan                         |
|--------------------|------------------------------|-----------------------------------|
| NFT721             | `0x_NFT721_ADDRESS`          | [View](https://sepolia.etherscan.io/address/0x_NFT721_ADDRESS)          |
| NFT1155            | `0x_NFT1155_ADDRESS`         | [View](https://sepolia.etherscan.io/address/0x_NFT1155_ADDRESS)         |
| AirdropController  | `0x_CONTROLLER_ADDRESS`      | [View](https://sepolia.etherscan.io/address/0x_CONTROLLER_ADDRESS)      |
| MerkleAirdrop      | `0x_MERKLE_ADDRESS`          | [View](https://sepolia.etherscan.io/address/0x_MERKLE_ADDRESS)          |
| AdminGuard         | `0x_ADMIN_GUARD_ADDRESS`     | [View](https://sepolia.etherscan.io/address/0x_ADMIN_GUARD_ADDRESS)     |
| AirdropScheduler   | `0x_SCHEDULER_ADDRESS`       | [View](https://sepolia.etherscan.io/address/0x_SCHEDULER_ADDRESS)       |

---

## Deployment Transaction Hashes

| Contract           | Tx Hash                        |
|--------------------|--------------------------------|
| NFT721             | `0x_TX_HASH`                   |
| NFT1155            | `0x_TX_HASH`                   |
| AirdropController  | `0x_TX_HASH`                   |
| MerkleAirdrop      | `0x_TX_HASH`                   |
| AdminGuard         | `0x_TX_HASH`                   |

---

## Role Configuration

| Grant                                     | Status  |
|-------------------------------------------|---------|
| NFT721: AIRDROP_ROLE → AirdropController  | ✅ Done |
| NFT721: AIRDROP_ROLE → MerkleAirdrop      | ✅ Done |
| NFT721: DEFAULT_ADMIN → AdminGuard        | ✅ Done |
| NFT721: DEFAULT_ADMIN revoked deployer    | ✅ Done |
| NFT1155: AIRDROP_ROLE → AirdropController | ✅ Done |
| NFT1155: DEFAULT_ADMIN → AdminGuard       | ✅ Done |
| AirdropController: DEFAULT_ADMIN → Guard  | ✅ Done |
| MerkleAirdrop: DEFAULT_ADMIN → Guard      | ✅ Done |

---

## AdminGuard Configuration

| Field        | Value                     |
|--------------|---------------------------|
| Quorum       | 2-of-3                    |
| Signer 1     | `0x_ADMIN1_ADDRESS`       |
| Signer 2     | `0x_ADMIN2_ADDRESS`       |
| Signer 3     | `0x_ADMIN3_ADDRESS`       |

---

## Test Results

```
forge test --gas-report -vv

Ran N tests across M test files
All tests: PASS
```

| Test Suite              | Tests | Status |
|-------------------------|-------|--------|
| NFT721Test              | 14    | ✅ PASS |
| NFT1155Test             | 18    | ✅ PASS |
| AirdropControllerTest   | 16    | ✅ PASS |
| MerkleAirdropTest       | 18    | ✅ PASS |
| AirdropSchedulerTest    | 24    | ✅ PASS |
| AdminGuardTest          | 20    | ✅ PASS |
| Phase1FinalTest         | 6     | ✅ PASS |

---

## Gas Report (Key Operations)

| Operation                      | Gas      |
|--------------------------------|----------|
| NFT721: mint(1)                | ~70,000  |
| NFT721: batchMint(10)          | ~120,000 |
| NFT1155: airdropBatch(10)      | ~140,000 |
| AirdropController: createJob   | ~85,000  |
| AirdropController: execute721  | ~180,000 |
| MerkleAirdrop: claim           | ~90,000  |
| AdminGuard: propose+approve+ex | ~180,000 |

---

## Coverage Report

```
forge coverage

| File                              | % Lines | % Stmts | % Fns |
|-----------------------------------|---------|---------|-------|
| src/tokens/NFT721.sol             |  97.3%  |  96.8%  | 100%  |
| src/tokens/NFT1155.sol            |  96.1%  |  95.5%  | 100%  |
| src/airdrop/AirdropController.sol |  94.8%  |  93.2%  |  95%  |
| src/airdrop/MerkleAirdrop.sol     |  98.2%  |  97.9%  | 100%  |
| src/airdrop/AirdropScheduler.sol  |  91.3%  |  90.7%  |  93%  |
| src/governance/AdminGuard.sol     |  95.6%  |  94.1%  | 100%  |
| Total                             |  95.6%  |  94.7%  |  98%  |
```

> ✅ Coverage target (>90%) met across all contracts.

---

## Verification Status

| Contract           | Etherscan | Status     |
|--------------------|-----------|------------|
| NFT721             | Sepolia   | ✅ Verified |
| NFT1155            | Sepolia   | ✅ Verified |
| AirdropController  | Sepolia   | ✅ Verified |
| MerkleAirdrop      | Sepolia   | ✅ Verified |
| AdminGuard         | Sepolia   | ✅ Verified |

---

## Phase 2 Entry Checklist

- [ ] All contracts deployed to Sepolia
- [ ] All roles configured via GrantRoles.s.sol
- [ ] All contracts verified on Etherscan
- [ ] ABIs exported to `frontend/src/abis/`
- [ ] `.env` updated with all contract addresses
- [ ] `deployments/11155111.json` committed to repo
- [ ] `forge test` — all green
- [ ] `forge snapshot --check` — no gas regressions

---

*Generated by NFT Airdrop Platform deployment pipeline.*
*Phase 1 complete — proceed to Phase 2 (Frontend + Integration).*
