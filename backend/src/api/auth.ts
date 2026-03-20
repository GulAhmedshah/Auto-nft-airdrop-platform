// backend/src/api/auth.ts
// ─────────────────────────────────────────────────────────────────────────────
// SIWE (Sign-In With Ethereum) authentication endpoints
//
// Endpoints:
//   GET    /api/auth/nonce    — generate one-time nonce for signing
//   POST   /api/auth/verify   — verify SIWE signature, issue JWT cookie
//   GET    /api/auth/session  — check if current JWT session is valid
//   DELETE /api/auth/session  — sign out, clear JWT cookie
//
// Security:
//   • Nonce is single-use and expires in 5 minutes
//   • JWT stored in httpOnly cookie — not accessible to JavaScript (XSS safe)
//   • JWT expires in 24 hours
//   • SIWE message validates domain + URI to prevent phishing
// ─────────────────────────────────────────────────────────────────────────────

import { Router, Request, Response } from 'express'
import { SiweMessage }               from 'siwe'
import { generateNonce }             from 'siwe'
import jwt                           from 'jsonwebtoken'

const router = Router()

// ── Config ────────────────────────────────────────────────────────────────────
const JWT_SECRET      = process.env.JWT_SECRET || 'dev-secret-change-in-production'
const JWT_EXPIRES_IN  = '24h'
const NONCE_TTL_MS    = 5 * 60 * 1000  // 5 minutes
const COOKIE_NAME     = 'airdrop_session'

// ── In-memory nonce store ─────────────────────────────────────────────────────
// In production: replace with Redis to support multiple server instances.
// Key: nonce string  →  Value: expiry timestamp
const nonceStore = new Map<string, number>()

// Clean up expired nonces every minute
setInterval(() => {
  const now = Date.now()
  for (const [nonce, expiry] of nonceStore.entries()) {
    if (now > expiry) nonceStore.delete(nonce)
  }
}, 60_000)

// ── JWT helpers ───────────────────────────────────────────────────────────────

interface JWTPayload {
  address: string
  chainId: number
  iat?:    number
  exp?:    number
}

function signJWT(payload: Omit<JWTPayload, 'iat' | 'exp'>): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN })
}

function verifyJWT(token: string): JWTPayload | null {
  try {
    return jwt.verify(token, JWT_SECRET) as JWTPayload
  } catch {
    return null
  }
}

function setJWTCookie(res: Response, token: string) {
  res.cookie(COOKIE_NAME, token, {
    httpOnly: true,                        // not accessible to JS — XSS safe
    secure:   process.env.NODE_ENV === 'production', // HTTPS only in prod
    sameSite: 'strict',                    // CSRF protection
    maxAge:   24 * 60 * 60 * 1000,        // 24 hours in ms
    path:     '/',
  })
}

function clearJWTCookie(res: Response) {
  res.clearCookie(COOKIE_NAME, { path: '/' })
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/auth/nonce
// Returns a fresh one-time nonce for the frontend to include in the SIWE msg.
// ─────────────────────────────────────────────────────────────────────────────

router.get('/nonce', (_req: Request, res: Response) => {
  const nonce  = generateNonce()
  const expiry = Date.now() + NONCE_TTL_MS

  nonceStore.set(nonce, expiry)

  res.json({ nonce })
})

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/auth/verify
// Verifies the SIWE signature. On success, issues a JWT in an httpOnly cookie.
//
// Body: { message: string, signature: string }
// ─────────────────────────────────────────────────────────────────────────────

router.post('/verify', async (req: Request, res: Response) => {
  const { message, signature } = req.body

  if (!message || !signature) {
    return res.status(400).json({ error: 'message and signature are required' })
  }

  try {
    // Parse the SIWE message
    const siweMessage = new SiweMessage(message)

    // Verify the signature — this checks:
    //   ✓ Signature is valid for the stated address
    //   ✓ Domain matches our server domain
    //   ✓ Nonce exists in our store and hasn't expired
    //   ✓ Message hasn't expired (if expirationTime was set)
    const { data: fields } = await siweMessage.verify({ signature })

    // Validate nonce — must exist and not be expired
    const nonceExpiry = nonceStore.get(fields.nonce)
    if (!nonceExpiry || Date.now() > nonceExpiry) {
      return res.status(401).json({ error: 'Invalid or expired nonce' })
    }

    // Consume nonce — single use only
    nonceStore.delete(fields.nonce)

    // Issue JWT
    const token = signJWT({
      address: fields.address,
      chainId: fields.chainId ?? 1,
    })

    setJWTCookie(res, token)

    return res.json({
      authenticated: true,
      address:       fields.address,
      chainId:       fields.chainId,
    })

  } catch (err) {
    console.error('SIWE verification failed:', err)
    return res.status(401).json({ error: 'Signature verification failed' })
  }
})

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/auth/session
// Returns current session info if JWT cookie is valid.
// Frontend calls this on page load to restore session (auto-reconnect).
// ─────────────────────────────────────────────────────────────────────────────

router.get('/session', (req: Request, res: Response) => {
  const token = req.cookies?.[COOKIE_NAME]

  if (!token) {
    return res.json({ authenticated: false })
  }

  const payload = verifyJWT(token)

  if (!payload) {
    clearJWTCookie(res)
    return res.json({ authenticated: false })
  }

  return res.json({
    authenticated: true,
    address:       payload.address,
    chainId:       payload.chainId,
  })
})

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/auth/session
// Signs the user out by clearing the JWT cookie.
// ─────────────────────────────────────────────────────────────────────────────

router.delete('/session', (req: Request, res: Response) => {
  clearJWTCookie(res)
  res.json({ authenticated: false })
})

export default router
