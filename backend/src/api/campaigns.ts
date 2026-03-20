// backend/src/api/campaigns.ts
import { Router, Request, Response } from 'express'
import { requireAuth }               from '../middleware/requireAuth'
import crypto                        from 'crypto'
import { airdropWorker }             from '../jobs/airdropWorker'

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

// ── In-memory store (replace with Prisma in production) ───────────────────────
export const campaignsStore: Campaign[] = []

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/campaigns
// ─────────────────────────────────────────────────────────────────────────────
router.get('/', requireAuth, (req: Request, res: Response) => {
  const userCampaigns = campaignsStore
    .filter(c => c.createdBy.toLowerCase() === req.user!.address.toLowerCase())
    .map(({ recipients, ...rest }) => rest) // exclude recipients array from list
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

  // Generate Merkle root for Merkle campaigns
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

  // Queue for execution
  const shouldExecuteNow = !scheduledAt || new Date(scheduledAt) <= new Date()
  if (shouldExecuteNow && distributionType === 'Direct') {
    // Fire and forget — worker updates status async
    airdropWorker.execute(campaign.id).catch(err => {
      console.error('Airdrop worker error:', err)
    })
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
// Merkle root generation (simplified — uses keccak256 of sorted leaves)
// In production: use the murky-equivalent JS library
// ─────────────────────────────────────────────────────────────────────────────
function generateMerkleRoot(recipients: Recipient[]): string {
  const { keccak256, encodePacked } = require('viem')

  const leaves = recipients.map(r =>
    keccak256(encodePacked(
      ['uint256', 'address', 'uint256'],
      [BigInt(r.index), r.address as `0x${string}`, BigInt(r.amount)]
    ))
  )

  // Simple binary tree root (for demonstration)
  // In production use: merkletreejs or equivalent
  let layer = leaves
  while (layer.length > 1) {
    const nextLayer: string[] = []
    for (let i = 0; i < layer.length; i += 2) {
      const left  = layer[i]
      const right = layer[i + 1] ?? layer[i]
      const combined = left < right
        ? keccak256(encodePacked(['bytes32', 'bytes32'], [left, right]))
        : keccak256(encodePacked(['bytes32', 'bytes32'], [right, left]))
      nextLayer.push(combined)
    }
    layer = nextLayer
  }

  return layer[0] ?? '0x' + '0'.repeat(64)
}

export default router
