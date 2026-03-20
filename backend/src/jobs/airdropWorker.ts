// backend/src/jobs/airdropWorker.ts
// ─────────────────────────────────────────────────────────────────────────────
// AirdropWorker — executes direct airdrop campaigns on-chain.
//
// In Phase 2 (P2-M4) this gets upgraded with BullMQ + Redis for production.
// For now it uses a simple in-process async queue sufficient for development.
//
// What it does:
//   1. Reads campaign from store
//   2. Splits recipients into batches of 500 (matches contract limit)
//   3. Calls AirdropController.executeAirdrop721/1155 via viem walletClient
//   4. Updates campaign status and tx hashes after each batch
// ─────────────────────────────────────────────────────────────────────────────

import { createPublicClient, createWalletClient, http, parseAbi } from 'viem'
import { privateKeyToAccount }                                     from 'viem/accounts'
import { sepolia }                                                 from 'viem/chains'
import { campaignsStore }                                          from '../api/campaigns'

const BATCH_SIZE       = 500
const CONTROLLER_ABI   = parseAbi([
  'function executeAirdrop721(bytes32 jobId, address[] calldata recipients, uint256 quantity, bool isFinalBatch) external',
  'function executeAirdrop1155(bytes32 jobId, address[] calldata recipients, uint256 tokenId, uint256 amountEach, bool isFinalBatch) external',
  'function createJob(bytes32 jobId, address tokenContract, uint8 tokenType, uint256 scheduledAt, uint256 expiresAt) external',
])

class AirdropWorker {
  private queue: string[] = []
  private processing      = false

  // ── Enqueue a campaign for execution ───────────────────────────────────────
  async execute(campaignId: string): Promise<void> {
    this.queue.push(campaignId)
    if (!this.processing) {
      this.processNext()
    }
  }

  // ── Process queue sequentially ─────────────────────────────────────────────
  private async processNext(): Promise<void> {
    if (this.queue.length === 0) {
      this.processing = false
      return
    }

    this.processing      = true
    const campaignId     = this.queue.shift()!
    const campaign       = campaignsStore.find(c => c.id === campaignId)

    if (!campaign) {
      this.processNext()
      return
    }

    // Update status to InProgress
    campaign.status     = 'InProgress'
    campaign.executedAt = new Date().toISOString()

    console.log(`[Worker] Starting campaign: ${campaign.name} (${campaign.id})`)
    console.log(`[Worker] Recipients: ${campaign.totalRecipients}`)

    try {
      const privateKey = process.env.PRIVATE_KEY
      const rpcUrl     = process.env.RPC_URL_LOCAL || 'http://127.0.0.1:8545'
      const controllerAddress = process.env.CONTROLLER_ADDRESS as `0x${string}` | undefined

      // ── If no private key or controller — simulate (dev mode) ─────────────
      if (!privateKey || !controllerAddress) {
        console.warn('[Worker] No PRIVATE_KEY or CONTROLLER_ADDRESS — simulating execution')
        await this.simulateExecution(campaign)
        this.processNext()
        return
      }

      // ── Real on-chain execution ────────────────────────────────────────────
      const account      = privateKeyToAccount(privateKey as `0x${string}`)
      const publicClient = createPublicClient({ chain: sepolia, transport: http(rpcUrl) })
      const walletClient = createWalletClient({ account, chain: sepolia, transport: http(rpcUrl) })

      // Split into batches of 500
      const batches = this.chunkArray(campaign.recipients, BATCH_SIZE)
      const jobId   = `0x${Buffer.from(campaign.id.replace(/-/g, '')).toString('hex').padEnd(64, '0')}` as `0x${string}`

      // Create controller job first
      await walletClient.writeContract({
        address:      controllerAddress,
        abi:          CONTROLLER_ABI,
        functionName: 'createJob',
        args: [
          jobId,
          campaign.contractAddress as `0x${string}`,
          campaign.tokenType === 'ERC721' ? 0 : 1,
          BigInt(0),
          BigInt(0),
        ],
      })

      let totalGas = 0

      for (let i = 0; i < batches.length; i++) {
        const batch       = batches[i]
        const isFinalBatch = i === batches.length - 1
        const addresses   = batch.map(r => r.address as `0x${string}`)

        let txHash: `0x${string}`

        if (campaign.tokenType === 'ERC721') {
          txHash = await walletClient.writeContract({
            address:      controllerAddress,
            abi:          CONTROLLER_ABI,
            functionName: 'executeAirdrop721',
            args:         [jobId, addresses, BigInt(batch[0].amount), isFinalBatch],
          })
        } else {
          txHash = await walletClient.writeContract({
            address:      controllerAddress,
            abi:          CONTROLLER_ABI,
            functionName: 'executeAirdrop1155',
            args:         [jobId, addresses, BigInt(campaign.tokenId ?? 1), BigInt(batch[0].amount), isFinalBatch],
          })
        }

        // Wait for confirmation
        const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash })
        totalGas     += Number(receipt.gasUsed)

        campaign.txHashes.push(txHash)
        campaign.processedCount += batch.length

        console.log(`[Worker] Batch ${i + 1}/${batches.length} mined: ${txHash}`)
      }

      campaign.status  = 'Completed'
      campaign.gasUsed = totalGas
      console.log(`[Worker] Campaign completed: ${campaign.name}`)

    } catch (err: unknown) {
      campaign.status       = 'Failed'
      campaign.errorMessage = err instanceof Error ? err.message : 'Unknown error'
      console.error(`[Worker] Campaign failed: ${campaign.name}`, err)
    }

    this.processNext()
  }

  // ── Simulate execution for development (no wallet needed) ──────────────────
  private async simulateExecution(campaign: typeof campaignsStore[0]): Promise<void> {
    const batches = this.chunkArray(campaign.recipients, BATCH_SIZE)

    for (let i = 0; i < batches.length; i++) {
      // Simulate network delay
      await new Promise(r => setTimeout(r, 500))

      const fakeTxHash = `0x${crypto.randomUUID().replace(/-/g, '')}` as `0x${string}`
      campaign.txHashes.push(fakeTxHash)
      campaign.processedCount += batches[i].length

      console.log(`[Worker:sim] Batch ${i + 1}/${batches.length} simulated: ${fakeTxHash}`)
    }

    campaign.status  = 'Completed'
    campaign.gasUsed = campaign.totalRecipients * 65000 // estimated
    console.log(`[Worker:sim] Campaign simulated: ${campaign.name}`)
  }

  private chunkArray<T>(arr: T[], size: number): T[][] {
    const chunks: T[][] = []
    for (let i = 0; i < arr.length; i += size) {
      chunks.push(arr.slice(i, i + size))
    }
    return chunks
  }
}

export const airdropWorker = new AirdropWorker()
