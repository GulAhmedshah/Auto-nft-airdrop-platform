// backend/src/jobs/airdropWorker.ts
// ─────────────────────────────────────────────────────────────────────────────
// Production BullMQ Airdrop Worker
//
// ── Architecture ─────────────────────────────────────────────────────────────
//
//   Campaign created (API)
//       │
//       ▼
//   AirdropQueue (Redis/BullMQ)   ← jobs stored here
//       │
//       ▼
//   AirdropWorker (this file)     ← processes jobs from queue
//       │
//       ├── Gas check            ← warn if gas spike
//       ├── Split into batches   ← 500 recipients max per tx
//       ├── Execute on-chain     ← via viem walletClient
//       ├── Retry on failure     ← 3 attempts, exponential backoff
//       └── Update campaign DB   ← Completed or Failed
//
// ── Why BullMQ over simple async? ────────────────────────────────────────────
//   • Jobs survive server restarts (stored in Redis, not memory)
//   • Built-in retry with exponential backoff
//   • Job concurrency control (don't hammer the RPC)
//   • Job history and monitoring via Bull Board UI
//   • Delayed jobs (execute at scheduledAt time)
// ─────────────────────────────────────────────────────────────────────────────

import { Queue, Worker, Job, QueueEvents } from 'bullmq'
import { redisConnection, QUEUE_NAMES }    from '../config/redis'
import {
  getPublicClient,
  getWalletClient,
  checkGasPrice,
  CONTROLLER_ABI,
}                                          from '../lib/viemClient'
import { campaignsStore, Campaign }        from '../api/campaigns'
import axios                               from 'axios'

// ── Job payload shape ─────────────────────────────────────────────────────────
export interface AirdropJobPayload {
  campaignId:        string
  contractAddress:   string
  tokenType:         'ERC721' | 'ERC1155'
  tokenId?:          number
  chainId:           number
  controllerAddress: string
  scheduledAt?:      string
}

// ── Constants ─────────────────────────────────────────────────────────────────
const BATCH_SIZE    = 500
const MAX_RETRIES   = 3
const BACKOFF_BASE  = 5_000   // 5 seconds base delay

// ─────────────────────────────────────────────────────────────────────────────
// Queue — where jobs are added
// ─────────────────────────────────────────────────────────────────────────────

export const airdropQueue = new Queue<AirdropJobPayload>(
  QUEUE_NAMES.AIRDROP,
  {
    connection:     redisConnection,
    defaultJobOptions: {
      attempts:     MAX_RETRIES,
      backoff: {
        type:  'exponential',
        delay: BACKOFF_BASE,
      },
      removeOnComplete: { count: 100 },  // keep last 100 completed jobs
      removeOnFail:     { count: 200 },  // keep last 200 failed jobs
    },
  }
)

// ─────────────────────────────────────────────────────────────────────────────
// Worker — processes jobs from the queue
// ─────────────────────────────────────────────────────────────────────────────

export const airdropWorker = new Worker<AirdropJobPayload>(
  QUEUE_NAMES.AIRDROP,
  async (job: Job<AirdropJobPayload>) => {
    const { campaignId, chainId, controllerAddress } = job.data

    console.log(`[Worker] Processing job ${job.id} — campaign: ${campaignId}`)

    // ── Find campaign in store ────────────────────────────────────────────────
    const campaign = campaignsStore.find(c => c.id === campaignId)
    if (!campaign) {
      throw new Error(`Campaign not found: ${campaignId}`)
    }

    // Update status to InProgress
    campaign.status     = 'InProgress'
    campaign.executedAt = new Date().toISOString()

    // ── Gas price check ───────────────────────────────────────────────────────
    const gasCheck = await checkGasPrice(chainId)
    console.log(`[Worker] ${gasCheck.message}`)

    if (!gasCheck.safe) {
      // Don't cancel — log warning and continue
      // In production: could delay the job and retry later
      console.warn('[Worker] Proceeding despite gas spike — check gas settings')
    }

    // ── Check if private key available ────────────────────────────────────────
    const hasPrivateKey = !!process.env.PRIVATE_KEY
    const hasController = !!controllerAddress && controllerAddress !== 'undefined'

    if (!hasPrivateKey || !hasController) {
      console.warn('[Worker] No PRIVATE_KEY or CONTROLLER_ADDRESS — simulating')
      await simulateExecution(campaign, job)
      return { simulated: true, campaignId }
    }

    // ── Real on-chain execution ───────────────────────────────────────────────
    await executeOnChain(campaign, job, chainId, controllerAddress as `0x${string}`)

    return { success: true, campaignId }
  },
  {
    connection:  redisConnection,
    concurrency: 2,        // process max 2 campaigns simultaneously
    limiter: {
      max:       10,       // max 10 jobs per duration
      duration:  60_000,   // per 60 seconds — rate limit RPC calls
    },
  }
)

// ─────────────────────────────────────────────────────────────────────────────
// Real on-chain execution
// ─────────────────────────────────────────────────────────────────────────────

async function executeOnChain(
  campaign:          Campaign,
  job:               Job<AirdropJobPayload>,
  chainId:           number,
  controllerAddress: `0x${string}`
): Promise<void> {
  const publicClient = getPublicClient(chainId)
  const walletClient = getWalletClient(chainId)

  const batches  = chunkArray(campaign.recipients, BATCH_SIZE)
  const jobIdHex = campaignIdToBytes32(campaign.id)
  let totalGas   = 0

  console.log(`[Worker] Executing ${batches.length} batches for ${campaign.name}`)

  // Create controller job first
  try {
    const createHash = await walletClient.writeContract({
      address:      controllerAddress,
      abi:          CONTROLLER_ABI,
      functionName: 'createJob',
      args: [
        jobIdHex,
        campaign.contractAddress as `0x${string}`,
        campaign.tokenType === 'ERC721' ? 0 : 1,
        BigInt(0),
        BigInt(0),
      ],
    })
    await publicClient.waitForTransactionReceipt({ hash: createHash })
    console.log(`[Worker] Job created on-chain: ${createHash}`)
  } catch (err) {
    // Job may already exist — continue
    console.warn('[Worker] createJob skipped (may already exist)')
  }

  // Execute batches
  for (let i = 0; i < batches.length; i++) {
    const batch        = batches[i]
    const isFinalBatch = i === batches.length - 1
    const addresses    = batch.map(r => r.address as `0x${string}`)

    // Update BullMQ job progress
    await job.updateProgress(Math.round((i / batches.length) * 100))

    let txHash: `0x${string}`

    if (campaign.tokenType === 'ERC721') {
      txHash = await walletClient.writeContract({
        address:      controllerAddress,
        abi:          CONTROLLER_ABI,
        functionName: 'executeAirdrop721',
        args: [
          jobIdHex,
          addresses,
          BigInt(batch[0]?.amount ?? 1),
          isFinalBatch,
        ],
      })
    } else {
      txHash = await walletClient.writeContract({
        address:      controllerAddress,
        abi:          CONTROLLER_ABI,
        functionName: 'executeAirdrop1155',
        args: [
          jobIdHex,
          addresses,
          BigInt(campaign.tokenId ?? 1),
          BigInt(batch[0]?.amount ?? 1),
          isFinalBatch,
        ],
      })
    }

    // Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({
      hash:          txHash,
      confirmations: 1,
    })

    totalGas              += Number(receipt.gasUsed)
    campaign.txHashes.push(txHash)
    campaign.processedCount += batch.length

    console.log(`[Worker] Batch ${i + 1}/${batches.length} mined: ${txHash}`)
  }

  // Mark completed
  campaign.status  = 'Completed'
  campaign.gasUsed = totalGas
  console.log(`[Worker] Campaign completed: ${campaign.name} — gas: ${totalGas}`)
}

// ─────────────────────────────────────────────────────────────────────────────
// Simulation mode (no private key)
// ─────────────────────────────────────────────────────────────────────────────

async function simulateExecution(
  campaign: Campaign,
  job:      Job<AirdropJobPayload>
): Promise<void> {
  const batches = chunkArray(campaign.recipients, BATCH_SIZE)

  for (let i = 0; i < batches.length; i++) {
    await new Promise(r => setTimeout(r, 300))
    await job.updateProgress(Math.round((i / batches.length) * 100))

    const fakeTxHash = `0x${crypto.randomUUID().replace(/-/g, '')}` as `0x${string}`
    campaign.txHashes.push(fakeTxHash)
    campaign.processedCount += batches[i].length

    console.log(`[Worker:sim] Batch ${i + 1}/${batches.length}: ${fakeTxHash}`)
  }

  campaign.status  = 'Completed'
  campaign.gasUsed = campaign.totalRecipients * 65_000
}

// ─────────────────────────────────────────────────────────────────────────────
// Worker event handlers
// ─────────────────────────────────────────────────────────────────────────────

airdropWorker.on('completed', (job) => {
  console.log(`[Worker] ✅ Job ${job.id} completed`)
})

airdropWorker.on('failed', (job, err) => {
  console.error(`[Worker] ❌ Job ${job?.id} failed:`, err.message)

  if (job) {
    const campaign = campaignsStore.find(c => c.id === job.data.campaignId)
    if (campaign) {
      // Only mark Failed if no more retries
      if (job.attemptsMade >= MAX_RETRIES) {
        campaign.status       = 'Failed'
        campaign.errorMessage = err.message
        sendFailureWebhook(campaign, err.message)
      }
    }
  }
})

airdropWorker.on('progress', (job, progress) => {
  console.log(`[Worker] Job ${job.id} progress: ${progress}%`)
})

// ─────────────────────────────────────────────────────────────────────────────
// Failure webhook
// ─────────────────────────────────────────────────────────────────────────────

async function sendFailureWebhook(campaign: Campaign, error: string): Promise<void> {
  const webhookUrl = process.env.WEBHOOK_URL
  if (!webhookUrl) return

  try {
    await axios.post(webhookUrl, {
      event:      'airdrop.failed',
      campaignId: campaign.id,
      name:       campaign.name,
      error,
      timestamp:  new Date().toISOString(),
    })
    console.log('[Worker] Failure webhook sent')
  } catch {
    console.error('[Worker] Failed to send webhook')
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: add campaign to queue
// ─────────────────────────────────────────────────────────────────────────────

export async function enqueueCampaign(
  campaign:          Campaign,
  controllerAddress: string,
  chainId:           number = 11155111
): Promise<void> {
  const payload: AirdropJobPayload = {
    campaignId:        campaign.id,
    contractAddress:   campaign.contractAddress,
    tokenType:         campaign.tokenType,
    tokenId:           campaign.tokenId,
    chainId,
    controllerAddress,
    scheduledAt:       campaign.scheduledAt,
  }

  // Delayed job if scheduledAt is in the future
  const delay = campaign.scheduledAt
    ? Math.max(0, new Date(campaign.scheduledAt).getTime() - Date.now())
    : 0

  await airdropQueue.add(
    `campaign-${campaign.id}`,
    payload,
    { delay }
  )

  console.log(
    `[Queue] Campaign enqueued: ${campaign.name}` +
    (delay > 0 ? ` (delayed ${Math.round(delay / 1000)}s)` : ' (immediate)')
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function chunkArray<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = []
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size))
  }
  return chunks
}

function campaignIdToBytes32(id: string): `0x${string}` {
  const hex = Buffer.from(id.replace(/-/g, '')).toString('hex')
  return `0x${hex.padEnd(64, '0')}` as `0x${string}`
}
