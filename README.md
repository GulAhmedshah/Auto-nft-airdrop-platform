# NFT Airdrop Platform

A production-grade, full-stack Web3 platform for deploying NFT collections and distributing them to thousands of wallets through automated airdrop campaigns.

Built with Solidity + Foundry (smart contracts) and React + Wagmi (frontend), deployed on EVM-compatible chains.

---

## What It Does

- **Deploy NFT Collections** — Deploy ERC-721 or ERC-1155 contracts directly from the browser in 4 steps
- **Manage Airdrop Campaigns** — Upload recipient CSVs, choose Direct or Merkle distribution, set schedules
- **Merkle Proof Claims** — Gas-efficient allowlist system where recipients self-claim using cryptographic proofs
- **Multi-Signature Security** — All critical admin operations require M-of-N wallet approvals
- **Scheduled Execution** — On-chain time controls enforce execution windows using block.timestamp
- **Wallet Authentication** — Sign-In With Ethereum (EIP-4361) — no passwords, no databases

---

## Tech Stack

### Smart Contracts
| Tool | Purpose |
|------|---------|
| Solidity ^0.8.24 | Contract language |
| Foundry | Compile, test, deploy |
| OpenZeppelin v5 | AccessControl, Pausable, MerkleProof, BitMaps |
| ERC721A | Gas-optimised batch NFT minting |
| Murky | Merkle tree generation in tests |

### Frontend
| Tool | Purpose |
|------|---------|
| React + Vite + TypeScript | UI framework |
| Wagmi v2 + Viem v2 | Ethereum interactions |
| RainbowKit | Wallet connection UI |
| TanStack Query | Async state management |

### Backend
| Tool | Purpose |
|------|---------|
| Node.js + Express | REST API |
| SIWE | Wallet-based authentication |
| JWT (httpOnly cookie) | Secure session management |
| Viem | On-chain execution from server |

---

## Smart Contract Architecture

```
src/
├── tokens/
│   ├── NFT721.sol          # ERC-721A + AccessControl + Pausable
│   └── NFT1155.sol         # ERC-1155 + AccessControl + Pausable
├── airdrop/
│   ├── AirdropController.sol   # Job-based orchestrator (ERC-721 + ERC-1155)
│   ├── MerkleAirdrop.sol       # Merkle proof claim system with BitMap
│   └── AirdropScheduler.sol    # Keeper-compatible time-controlled execution
└── governance/
    └── AdminGuard.sol      # On-chain M-of-N multi-signature quorum guard
```

### Contract Interactions

```
Admin Wallet
    │
    ├── NFT721 / NFT1155      (token contracts)
    │       │
    │       └── AIRDROP_ROLE ──► AirdropController  (pushes tokens to recipients)
    │       └── AIRDROP_ROLE ──► MerkleAirdrop      (recipients self-claim)
    │       └── DEFAULT_ADMIN ──► AdminGuard        (multi-sig required)
    │
    └── AirdropScheduler       (Chainlink-compatible keeper)
              │
              └── triggers ──► AirdropController at scheduled time
```

---

## Key Features Explained

### Gas-Optimised Batch Minting (ERC721A)
Minting 100 NFTs in one transaction costs roughly the same as minting 1 with standard ERC-721. ERC721A achieves this by batching storage writes.

### Merkle Proof Airdrop
Instead of storing 10,000 addresses on-chain (expensive), we store a single 32-byte Merkle root. Recipients prove eligibility by submitting a cryptographic proof. Claimed status tracked in a BitMap — 256x more gas-efficient than a boolean mapping.

### Multi-Signature Admin Guard
All critical operations (cancel jobs, update Merkle roots, pause contracts) require M-of-N admin approvals through `AdminGuard.sol` — no single wallet can act unilaterally.

### Sign-In With Ethereum (SIWE)
Authentication without passwords. Users sign a message with their wallet proving ownership. Server verifies the signature and issues a JWT stored in an httpOnly cookie — invisible to JavaScript, safe from XSS attacks.

---

## Phase 1 — Smart Contracts

| Iteration | Contract | Description |
|-----------|----------|-------------|
| P1-I2 | NFT721.sol | ERC-721A base contract |
| P1-I3 | NFT1155.sol | ERC-1155 multi-token contract |
| P1-I4 | AirdropController.sol | Basic distribution controller |
| P1-I5 | MerkleAirdrop.sol | Merkle proof claim system |
| P1-I6 | AirdropScheduler.sol | Time-controlled execution |
| P1-I7 | AdminGuard.sol | Multi-sig security layer |
| P1-I8 | Deploy + GrantRoles | Production deployment scripts |

### Test Results
```
forge test --gas-report -vv

Ran 6 test suites: 145 tests passed, 0 failed
```

| Test Suite | Tests |
|------------|-------|
| NFT721Test | 29 ✅ |
| NFT1155Test | 40 ✅ |
| AirdropControllerTest | 16 ✅ |
| MerkleAirdropTest | 18 ✅ |
| AirdropSchedulerTest | 26 ✅ |
| AdminGuardTest | 25 ✅ |
| Phase1FinalTest | 6 ✅ |

---

## Phase 2 — Frontend + Backend

| Module | Description | Status |
|--------|-------------|--------|
| P2-M1 | Wallet Connection + SIWE Auth | ✅ Complete |
| P2-M2 | NFT Deploy Wizard (4-step) | ✅ Complete |
| P2-M3 | Campaign Manager + CSV Upload | ✅ Complete |
| P2-M4 | BullMQ Worker Queue | 🔄 In Progress |
| P2-M5 | User NFT Portfolio | ⏳ Planned |
| P2-M6 | Transaction Tracking | ⏳ Planned |
| P2-M7 | Analytics Dashboard | ⏳ Planned |

---

## Getting Started

### Prerequisites
- Node.js v20+
- Foundry (`curl -L https://foundry.paradigm.xyz | bash`)
- MetaMask browser extension

### 1. Clone and install

```bash
git clone https://github.com/YOUR_USERNAME/nft-airdrop-platform.git
cd nft-airdrop-platform

# Install Foundry dependencies
forge install

# Install frontend dependencies
cd frontend && npm install

# Install backend dependencies
cd ../backend && npm install
```

### 2. Configure environment

```bash
cp .env.example .env
# Fill in your values:
# PRIVATE_KEY, RPC_URL_SEPOLIA, ETHERSCAN_API_KEY
```

### 3. Run tests

```bash
forge test -vv
```

### 4. Deploy contracts

```bash
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL_SEPOLIA \
  --private-key $PRIVATE_KEY \
  --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### 5. Run the dApp

```bash
# Terminal 1 — Backend
cd backend && npm run dev

# Terminal 2 — Frontend
cd frontend && npm run dev
```

Open http://localhost:5173

---

## Deployed Contracts (Sepolia Testnet)

| Contract | Address |
|----------|---------|
| NFT721 | `0x_YOUR_ADDRESS` |
| NFT1155 | `0x_YOUR_ADDRESS` |
| AirdropController | `0x_YOUR_ADDRESS` |
| MerkleAirdrop | `0x_YOUR_ADDRESS` |
| AdminGuard | `0x_YOUR_ADDRESS` |

---

## Security

- No private keys stored on server
- All signing happens in user's wallet
- JWT stored in httpOnly cookie (XSS safe)
- Multi-sig required for all admin operations
- OpenZeppelin audited base contracts
- Merkle proof prevents double-claiming
- BitMap tracking prevents replay attacks

---

## License

MIT

---

## Author

Built by **Gul Ahmed** — learning Web3 development by building production-grade projects.

- GitHub: [@YOUR_USERNAME](https://github.com/YOUR_USERNAME)
- Twitter/X: [@YOUR_HANDLE](https://twitter.com/YOUR_HANDLE)
