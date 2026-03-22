// backend/src/api/claims.ts
// ─────────────────────────────────────────────────────────────────────────────
// Claims API — checks if an address is eligible for a Merkle airdrop
// and returns their proof so they can claim on-chain.
//
// GET /api/claims/:address
//   Returns: { eligible, index, amount, proof }
//   Used by ClaimPage.tsx to check eligibility before submitting tx
// ─────────────────────────────────────────────────────────────────────────────

import { Router, Request, Response } from 'express'
import crypto                        from 'crypto'
import { campaignsStore }            from './campaigns'

const router = Router()

// ── GET /api/claims/:address ──────────────────────────────────────────────────
router.get('/:address', (req: Request, res: Response) => {
  const { address } = req.params

  if (!address || !/^0x[0-9a-fA-F]{40}$/.test(address)) {
    return res.status(400).json({ error: 'Invalid Ethereum address' })
  }

  // Find Merkle campaigns that include this address
  const merkleCampaigns = campaignsStore.filter(
    c => c.distributionType === 'Merkle' && c.status !== 'Failed'
  )

  for (const campaign of merkleCampaigns) {
    const recipientIndex = campaign.recipients.findIndex(
      r => r.address.toLowerCase() === address.toLowerCase()
    )

    if (recipientIndex === -1) continue

    const recipient = campaign.recipients[recipientIndex]

    // Generate proof for this recipient
    const proof = generateProof(campaign.recipients, recipientIndex)

    return res.json({
      eligible:   true,
      index:      recipient.index,
      amount:     recipient.amount,
      proof,
      campaignId: campaign.id,
      merkleRoot: campaign.merkleRoot,
    })
  }

  return res.status(404).json({
    eligible: false,
    message:  'Address not found in any active Merkle airdrop.',
  })
})

// ── Merkle proof generation ───────────────────────────────────────────────────
function generateProof(
  recipients: { index: number; address: string; amount: number }[],
  targetIndex: number
): string[] {
  // Build leaves
  const leaves = recipients.map(r =>
    crypto.createHash('sha256')
      .update(`${r.index}${r.address.toLowerCase()}${r.amount}`)
      .digest('hex')
  )

  const proof: string[] = []
  let idx = targetIndex

  // Build tree layer by layer
  let layer = [...leaves]

  while (layer.length > 1) {
    const nextLayer: string[] = []

    for (let i = 0; i < layer.length; i += 2) {
      const left  = layer[i]
      const right = layer[i + 1] ?? layer[i]

      // Add sibling to proof
      if (i === idx || i + 1 === idx) {
        const sibling = i === idx ? right : left
        if (sibling !== layer[idx]) {
          proof.push('0x' + sibling)
        }
        idx = Math.floor(i / 2)
      }

      const pair    = left < right ? left + right : right + left
      const combined = crypto.createHash('sha256').update(pair).digest('hex')
      nextLayer.push(combined)
    }

    layer = nextLayer
  }

  return proof
}

export default router
