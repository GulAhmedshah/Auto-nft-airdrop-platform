// backend/src/middleware/requireAuth.ts
// ─────────────────────────────────────────────────────────────────────────────
// Express middleware that protects routes requiring authentication.
// Reads the JWT from the httpOnly cookie and attaches the payload to req.
//
// Usage:
//   router.get('/protected', requireAuth, (req, res) => {
//     res.json({ address: req.user.address })
//   })
// ─────────────────────────────────────────────────────────────────────────────

import { Request, Response, NextFunction } from 'express'
import jwt                                 from 'jsonwebtoken'

const JWT_SECRET  = process.env.JWT_SECRET || 'dev-secret-change-in-production'
const COOKIE_NAME = 'airdrop_session'

// Extend Express Request to include our user payload
declare global {
  namespace Express {
    interface Request {
      user?: {
        address: string
        chainId: number
      }
    }
  }
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const token = req.cookies?.[COOKIE_NAME]

  if (!token) {
    return res.status(401).json({ error: 'Not authenticated' })
  }

  try {
    const payload = jwt.verify(token, JWT_SECRET) as {
      address: string
      chainId: number
    }
    req.user = payload
    return next()
  } catch {
    return res.status(401).json({ error: 'Session expired. Please sign in again.' })
  }
}

// ── requireAdmin — additionally checks if address is in the admin list ────────
// In production: check against AdminGuard's ADMIN_ROLE on-chain, or a DB table.
export function requireAdmin(req: Request, res: Response, next: NextFunction) {
  requireAuth(req, res, () => {
    const adminAddresses = (process.env.ADMIN_ADDRESSES || '')
      .split(',')
      .map(a => a.trim().toLowerCase())

    const userAddress = req.user?.address?.toLowerCase()

    if (!userAddress || !adminAddresses.includes(userAddress)) {
      return res.status(403).json({ error: 'Admin access required' })
    }

    return next()
  })
}
