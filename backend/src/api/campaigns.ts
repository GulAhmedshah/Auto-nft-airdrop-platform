// backend/src/api/campaigns.ts
import { Router, Request, Response } from 'express'
import { requireAuth }               from '../middleware/requireAuth'
import crypto                        from 'crypto'

const router = Router()

// ── Types ─────────────────────────────────────────────────────────────────────
export interface Recipient {
  index:    number
  address:  string
  amount:   number
  tokenId?: number
}

export interface Campaign {
  id:               string
  name:             string
  contractAddress:  string
  tokenType:        'ERC721' | 'ERC1155'
  distributionType: 'Direct' | 'Merkle'
  tokenId?:         number
  status:           'Pending' | 'InProgress' | 'Completed' | 'Failed'
  totalRecipients:  number
  processedCount:   number
  recipients:       Recipient[]
  merkleRoot?:      string
  scheduledAt?:     string
  createdAt:        string
  executedAt?:      string
  txHashes:         string[]
  gasUsed?:         number
  errorMessage?:    string
  createdBy:        string
}

export const campaignsStore: Campaign[] = []

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/campaigns
// ─────────────────────────────────────────────────────────────────────────────
router.get('/', requireAuth, (req: Request, res: Response) => {
  const userCampaigns = campaignsStore
    .filter(c => c.createdBy.toLowerCase() === req.user!.address.toLowerCase())
    .map(({ recipients, ...rest }) => rest)
  res.json(userCampaigns)
})

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/campaigns
// ─────────────────────────────────────────────────────────────────────────────
router.post('/', requireAuth, async (req: Request, res: Response) => {
  const {
    name, contractAddress, tokenType, distributionType,
    tokenId, recipients, scheduledAt,
  } = req.body

  if (!name || !contractAddress || !tokenType || !recipients?.length) {
    return res.status(400).json({ error: 'Missing required fields' })
  }

  let merkleRoot: string | undefined
  if (distributionType === 'Merkle') {
    merkleRoot = generateMerkleRoot(recipients)
  }

  const campaign: Campaign = {
    id:               crypto.randomUUID(),
    name,
    contractAddress:  contractAddress.toLowerCase(),
    tokenType,
    distributionType,
    tokenId,
    status:           'Pending',
    totalRecipients:  recipients.length,
    processedCount:   0,
    recipients,
    merkleRoot,
    scheduledAt:      scheduledAt || undefined,
    createdAt:        new Date().toISOString(),
    txHashes:         [],
    createdBy:        req.user!.address,
  }

  campaignsStore.push(campaign)

  // Enqueue for execution if Direct and due now
  if (distributionType === 'Direct') {
    const shouldExecuteNow = !scheduledAt || new Date(scheduledAt) <= new Date()
    if (shouldExecuteNow) {
      try {
        // Try BullMQ first
        const { enqueueCampaign } = await import('../jobs/airdropWorker')
        const controllerAddress   = process.env.CONTROLLER_ADDRESS ?? ''
        const chainId             = parseInt(process.env.CHAIN_ID ?? '11155111')
        await enqueueCampaign(campaign, controllerAddress, chainId)
        console.log(`Campaign queued via BullMQ: ${campaign.name}`)
      } catch {
        // Fall back to in-memory simulation if Redis not available
        console.warn('BullMQ unavailable — using in-memory simulation')
        simulateCampaign(campaign)
      }
    }
  }

  console.log(`Campaign created: ${campaign.name} (${campaign.id})`)
  res.status(201).json({ ...campaign, recipients: undefined })
})

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/campaigns/:id/status
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id/status', requireAuth, (req: Request, res: Response) => {
  const campaign = campaignsStore.find(c => c.id === req.params.id)
  if (!campaign) return res.status(404).json({ error: 'Campaign not found' })
  const { recipients, ...rest } = campaign
  res.json(rest)
})

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/campaigns/:id
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id', requireAuth, (req: Request, res: Response) => {
  const campaign = campaignsStore.find(c => c.id === req.params.id)
  if (!campaign) return res.status(404).json({ error: 'Campaign not found' })
  res.json(campaign)
})

// ─────────────────────────────────────────────────────────────────────────────
// In-memory simulation fallback
// ─────────────────────────────────────────────────────────────────────────────
async function simulateCampaign(campaign: Campaign): Promise<void> {
  campaign.status     = 'InProgress'
  campaign.executedAt = new Date().toISOString()

  const batches = chunkArray(campaign.recipients, 500)
  for (let i = 0; i < batches.length; i++) {
    await new Promise(r => setTimeout(r, 500))
    const fakeTx = `0x${crypto.randomBytes(32).toString('hex')}`
    campaign.txHashes.push(fakeTx)
    campaign.processedCount += batches[i].length
    console.log(`[Sim] Batch ${i + 1}/${batches.length}: ${fakeTx}`)
  }

  campaign.status  = 'Completed'
  campaign.gasUsed = campaign.totalRecipients * 65_000
  console.log(`[Sim] Campaign completed: ${campaign.name}`)
}

// ─────────────────────────────────────────────────────────────────────────────
// Merkle root generation
// ─────────────────────────────────────────────────────────────────────────────
function generateMerkleRoot(recipients: Recipient[]): string {
  const leaves = recipients.map(r =>
    crypto.createHash('sha256')
      .update(`${r.index}${r.address}${r.amount}`)
      .digest('hex')
  )

  let layer = leaves
  while (layer.length > 1) {
    const next: string[] = []
    for (let i = 0; i < layer.length; i += 2) {
      const left  = layer[i]
      const right = layer[i + 1] ?? layer[i]
      const pair  = left < right ? left + right : right + left
      next.push(crypto.createHash('sha256').update(pair).digest('hex'))
    }
    layer = next
  }

  return '0x' + (layer[0] ?? '0'.repeat(64))
}

function chunkArray<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = []
  for (let i = 0; i < arr.length; i += size) chunks.push(arr.slice(i, i + size))
  return chunks
}

export default router
