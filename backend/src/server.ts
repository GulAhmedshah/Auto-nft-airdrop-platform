// backend/src/server.ts
import express           from 'express'
import cors              from 'cors'
import cookieParser      from 'cookie-parser'
import authRouter        from './api/auth'
import collectionsRouter from './api/collections'
import campaignsRouter   from './api/campaigns'
import { startScheduler } from './jobs/scheduler'

const app  = express()
const PORT = process.env.PORT || 3001

app.use(express.json())
app.use(cookieParser())
app.use(cors({
  origin:      process.env.FRONTEND_URL || 'http://localhost:5173',
  credentials: true,
}))

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/api/auth',        authRouter)
app.use('/api/collections', collectionsRouter)
app.use('/api/ipfs',        collectionsRouter)
app.use('/api/campaigns',   campaignsRouter)

app.get('/health', (_, res) => res.json({ status: 'ok', timestamp: new Date() }))

// ── Start server ──────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`Backend running on http://localhost:${PORT}`)

  // Start the campaign scheduler
  // Checks for due campaigns every 60 seconds and enqueues them
  try {
    startScheduler()
  } catch (err) {
    console.warn('[Server] Scheduler failed to start (Redis may not be available):', err)
    console.warn('[Server] Campaigns will use in-memory simulation instead')
  }
})

export default app
