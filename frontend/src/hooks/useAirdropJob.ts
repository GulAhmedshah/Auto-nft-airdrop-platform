// frontend/src/hooks/useAirdropJob.ts
// ─────────────────────────────────────────────────────────────────────────────
// useAirdropJob — polls campaign status every 5 seconds during execution.
// Stops polling when status reaches Completed or Failed.
// ─────────────────────────────────────────────────────────────────────────────

import { useState, useEffect, useCallback, useRef } from 'react'
import axios from 'axios'

const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001'

export type CampaignStatus = 'Pending' | 'InProgress' | 'Completed' | 'Failed'

export interface CampaignJob {
  id:               string
  name:             string
  contractAddress:  string
  tokenType:        'ERC721' | 'ERC1155'
  distributionType: 'Direct' | 'Merkle'
  status:           CampaignStatus
  totalRecipients:  number
  processedCount:   number
  merkleRoot?:      string
  scheduledAt?:     string
  createdAt:        string
  executedAt?:      string
  txHashes:         string[]
  gasUsed?:         number
  errorMessage?:    string
}

export interface UseAirdropJobReturn {
  campaign:   CampaignJob | null
  isLoading:  boolean
  isPolling:  boolean
  error:      string | null
  refresh:    () => void
}

export function useAirdropJob(campaignId: string | null): UseAirdropJobReturn {
  const [campaign,  setCampaign]  = useState<CampaignJob | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [isPolling, setIsPolling] = useState(false)
  const [error,     setError]     = useState<string | null>(null)
  const intervalRef               = useRef<ReturnType<typeof setInterval> | null>(null)

  const fetchStatus = useCallback(async () => {
    if (!campaignId) return
    try {
      const res = await axios.get(
        `${API_BASE}/api/campaigns/${campaignId}/status`,
        { withCredentials: true }
      )
      const data: CampaignJob = res.data
      setCampaign(data)

      // Stop polling when terminal state reached
      if (data.status === 'Completed' || data.status === 'Failed') {
        setIsPolling(false)
        if (intervalRef.current) {
          clearInterval(intervalRef.current)
          intervalRef.current = null
        }
      }
    } catch (err) {
      setError('Failed to fetch campaign status')
    }
  }, [campaignId])

  // Initial fetch + start polling for active campaigns
  useEffect(() => {
    if (!campaignId) return

    setIsLoading(true)
    fetchStatus().finally(() => setIsLoading(false))

    // Start polling every 5 seconds
    setIsPolling(true)
    intervalRef.current = setInterval(fetchStatus, 5_000)

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current)
    }
  }, [campaignId, fetchStatus])

  return {
    campaign,
    isLoading,
    isPolling,
    error,
    refresh: fetchStatus,
  }
}
