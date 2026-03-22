// backend/src/jobs/scheduler.ts
// ─────────────────────────────────────────────────────────────────────────────
// Airdrop Scheduler — runs every 60 seconds
//
// Checks for campaigns where:
//   status = Pending  AND  scheduledAt <= now
//
// Enqueues them in BullMQ for the worker to process.
//
// This is the "trigger" — the worker is the "executor".
// ─────────────────────────────────────────────────────────────────────────────

import { campaignsStore } from '../api/campaigns'
import { enqueueCampaign } from './airdropWorker'

const SCHEDULER_INTERVAL_MS = 60_000  // 60 seconds
const CONTROLLER_ADDRESS    = process.env.CONTROLLER_ADDRESS ?? ''
const CHAIN_ID              = parseInt(process.env.CHAIN_ID ?? '11155111')

// ── Track which campaigns have been enqueued to avoid duplicates ───────────────
const enqueuedCampaigns = new Set<string>()

// ─────────────────────────────────────────────────────────────────────────────
// Main scheduler function
// ─────────────────────────────────────────────────────────────────────────────

async function checkAndEnqueue(): Promise<void> {
  const now = new Date()

  const dueCampaigns = campaignsStore.filter(campaign => {
    // Skip already enqueued or non-pending
    if (enqueuedCampaigns.has(campaign.id)) return false
    if (campaign.status !== 'Pending')       return false
    if (campaign.distributionType !== 'Direct') return false

    // Check if scheduled time has arrived
    if (!campaign.scheduledAt) return true  // immediate
    return new Date(campaign.scheduledAt) <= now
  })

  if (dueCampaigns.length === 0) return

  console.log(`[Scheduler] Found ${dueCampaigns.length} due campaign(s)`)

  for (const campaign of dueCampaigns) {
    try {
      await enqueueCampaign(campaign, CONTROLLER_ADDRESS, CHAIN_ID)
      enqueuedCampaigns.add(campaign.id)
      console.log(`[Scheduler] Enqueued: ${campaign.name} (${campaign.id})`)
    } catch (err) {
      console.error(`[Scheduler] Failed to enqueue ${campaign.id}:`, err)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Start the scheduler
// ─────────────────────────────────────────────────────────────────────────────

let schedulerTimer: ReturnType<typeof setInterval> | null = null

export function startScheduler(): void {
  if (schedulerTimer) return  // already running

  console.log(`[Scheduler] Started — checking every ${SCHEDULER_INTERVAL_MS / 1000}s`)

  // Run immediately on start
  checkAndEnqueue().catch(console.error)

  // Then run on interval
  schedulerTimer = setInterval(() => {
    checkAndEnqueue().catch(console.error)
  }, SCHEDULER_INTERVAL_MS)
}

export function stopScheduler(): void {
  if (schedulerTimer) {
    clearInterval(schedulerTimer)
    schedulerTimer = null
    console.log('[Scheduler] Stopped')
  }
}
