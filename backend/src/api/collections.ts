// backend/src/api/collections.ts
// ─────────────────────────────────────────────────────────────────────────────
// Collections API — stores deployed NFT collection records
//
// Endpoints:
//   GET    /api/collections        — list all deployed collections
//   POST   /api/collections        — save a newly deployed collection
//   GET    /api/collections/:id    — get single collection
//   POST   /api/ipfs/upload        — upload file to IPFS via Pinata
// ─────────────────────────────────────────────────────────────────────────────

import { Router, Request, Response } from 'express'
import { requireAuth }               from '../middleware/requireAuth'
import crypto                        from 'crypto'
import FormData                      from 'form-data'
import axios                         from 'axios'

const router = Router()

// ── In-memory store (replace with Prisma/DB in production) ───────────────────
interface Collection {
  id:              string
  contractAddress: string
  tokenType:       'ERC721' | 'ERC1155'
  name:            string
  symbol:          string
  chainId:         number
  txHash:          string
  deployedBy:      string
  deployedAt:      string
}

const collectionsStore: Collection[] = []

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/collections
// ─────────────────────────────────────────────────────────────────────────────

router.get('/', requireAuth, (req: Request, res: Response) => {
  // Return collections deployed by this user or all (admin sees all)
  const userCollections = collectionsStore.filter(
    c => c.deployedBy.toLowerCase() === req.user!.address.toLowerCase()
  )
  res.json(userCollections)
})

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/collections
// Save a newly deployed collection record
// ─────────────────────────────────────────────────────────────────────────────

router.post('/', requireAuth, (req: Request, res: Response) => {
  const { contractAddress, tokenType, txHash, chainId } = req.body

  if (!contractAddress || !tokenType || !txHash || !chainId) {
    return res.status(400).json({ error: 'Missing required fields' })
  }

  // Check for duplicate
  const exists = collectionsStore.find(
    c => c.contractAddress.toLowerCase() === contractAddress.toLowerCase()
  )
  if (exists) return res.json(exists)

  const collection: Collection = {
    id:              crypto.randomUUID(),
    contractAddress: contractAddress.toLowerCase(),
    tokenType,
    name:            req.body.name    || 'Unknown',
    symbol:          req.body.symbol  || '???',
    chainId:         Number(chainId),
    txHash,
    deployedBy:      req.user!.address,
    deployedAt:      new Date().toISOString(),
  }

  collectionsStore.push(collection)

  console.log(`Collection saved: ${collection.name} at ${collection.contractAddress}`)
  res.status(201).json(collection)
})

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/collections/:id
// ─────────────────────────────────────────────────────────────────────────────

router.get('/:id', requireAuth, (req: Request, res: Response) => {
  const collection = collectionsStore.find(c => c.id === req.params.id)
  if (!collection) return res.status(404).json({ error: 'Collection not found' })
  res.json(collection)
})

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/ipfs/upload
// Upload image/metadata to IPFS via Pinata
//
// In production: use multer for file handling, pin to Pinata
// Here we return a mock URI for development
// ─────────────────────────────────────────────────────────────────────────────

router.post('/upload', requireAuth, async (req: Request, res: Response) => {
  const PINATA_API_KEY    = process.env.PINATA_API_KEY
  const PINATA_SECRET_KEY = process.env.PINATA_SECRET

  // ── Development mock ──────────────────────────────────────────────────────
  if (!PINATA_API_KEY || !PINATA_SECRET_KEY) {
    console.warn('Pinata keys not set — returning mock IPFS URI')
    const mockHash = crypto.randomBytes(16).toString('hex')
    return res.json({
      baseURI:  `ipfs://Qm${mockHash}/`,
      ipfsHash: `Qm${mockHash}`,
      mock:     true,
    })
  }

  // ── Production: pin to Pinata ─────────────────────────────────────────────
  try {
    const formData = new FormData()
    // req.file would come from multer middleware
    // For now we demonstrate the Pinata API call pattern
    const pinataRes = await axios.post(
      'https://api.pinata.cloud/pinning/pinFileToIPFS',
      formData,
      {
        headers: {
          ...formData.getHeaders(),
          pinata_api_key:        PINATA_API_KEY,
          pinata_secret_api_key: PINATA_SECRET_KEY,
        },
      }
    )

    const ipfsHash = pinataRes.data.IpfsHash
    res.json({
      baseURI:  `ipfs://${ipfsHash}/`,
      ipfsHash,
      mock:     false,
    })
  } catch (err) {
    console.error('Pinata upload failed:', err)
    res.status(500).json({ error: 'IPFS upload failed' })
  }
})

export default router
