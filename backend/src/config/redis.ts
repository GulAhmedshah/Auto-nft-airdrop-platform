// backend/src/config/redis.ts
// ─────────────────────────────────────────────────────────────────────────────
// Redis connection configuration for BullMQ.
//
// BullMQ uses Redis as its job store — every queued job, its status,
// retry count, and result are stored in Redis.
//
// ── Local development ─────────────────────────────────────────────────────────
//   Install Redis locally:
//     Windows: https://github.com/microsoftarchive/redis/releases
//     Or use Docker: docker run -d -p 6379:6379 redis:alpine
//
//   Then set in .env:
//     REDIS_URL=redis://localhost:6379
//
// ── Production ───────────────────────────────────────────────────────────────
//   Use Redis Cloud (free tier): https://redis.com/try-free/
//   Or Upstash (serverless Redis): https://upstash.com
//   Set: REDIS_URL=redis://default:PASSWORD@hostname:port
// ─────────────────────────────────────────────────────────────────────────────

export const redisConnection = {
  //host: process.env.REDIS_HOST ?? 'localhost',
  // CORRECT — forces IPv4
host: process.env.REDIS_HOST ?? '127.0.0.1',
  port: parseInt(process.env.REDIS_PORT ?? '6379'),
  password: process.env.REDIS_PASSWORD ?? undefined,
  // Reconnect automatically if connection drops
  maxRetriesPerRequest: null, // required by BullMQ
}

export const REDIS_URL = process.env.REDIS_URL ?? 'redis://localhost:6379'

// ── Queue names ───────────────────────────────────────────────────────────────
export const QUEUE_NAMES = {
  AIRDROP:   'airdrop-execution',
  SCHEDULER: 'airdrop-scheduler',
} as const
