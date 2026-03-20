// frontend/src/pages/admin/CampaignList.tsx
import { useState, useEffect } from 'react'
import axios                   from 'axios'
import { CampaignJob }         from '../../hooks/useAirdropJob'

const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001'

const STATUS_COLORS: Record<string, { bg: string; color: string }> = {
  Pending:    { bg: '#f59e0b15', color: '#f59e0b' },
  InProgress: { bg: '#3b82f615', color: '#60a5fa' },
  Completed:  { bg: '#22c55e15', color: '#22c55e' },
  Failed:     { bg: '#ef444415', color: '#ef4444' },
}

type SortKey = 'name' | 'status' | 'createdAt' | 'totalRecipients'

interface Props {
  onSelect?: (id: string) => void
  onCreateNew?: () => void
}

export default function CampaignList({ onSelect, onCreateNew }: Props) {
  const [campaigns, setCampaigns] = useState<CampaignJob[]>([])
  const [loading,   setLoading]   = useState(true)
  const [sortKey,   setSortKey]   = useState<SortKey>('createdAt')
  const [sortAsc,   setSortAsc]   = useState(false)

  useEffect(() => {
    fetchCampaigns()
    // Refresh every 10 seconds for live status updates
    const timer = setInterval(fetchCampaigns, 10_000)
    return () => clearInterval(timer)
  }, [])

  async function fetchCampaigns() {
    try {
      const res = await axios.get(`${API_BASE}/api/campaigns`, {
        withCredentials: true,
      })
      setCampaigns(res.data)
    } catch {
      // Silently fail on refresh
    } finally {
      setLoading(false)
    }
  }

  function toggleSort(key: SortKey) {
    if (sortKey === key) setSortAsc(a => !a)
    else { setSortKey(key); setSortAsc(true) }
  }

  const sorted = [...campaigns].sort((a, b) => {
    let va: string | number = a[sortKey] as string | number ?? ''
    let vb: string | number = b[sortKey] as string | number ?? ''
    if (typeof va === 'string') va = va.toLowerCase()
    if (typeof vb === 'string') vb = vb.toLowerCase()
    if (va < vb) return sortAsc ? -1 : 1
    if (va > vb) return sortAsc ? 1 : -1
    return 0
  })

  function SortIcon({ k }: { k: SortKey }) {
    if (sortKey !== k) return <span style={{ color: '#444' }}> ↕</span>
    return <span style={{ color: '#7C3AED' }}>{sortAsc ? ' ↑' : ' ↓'}</span>
  }

  if (loading) return (
    <div style={{ padding: '32px', color: '#888', fontFamily: 'sans-serif' }}>
      Loading campaigns...
    </div>
  )

  return (
    <div style={{ padding: '32px', maxWidth: '960px', margin: '0 auto',
                  color: '#fff', fontFamily: 'sans-serif' }}>

      <div style={{ display: 'flex', justifyContent: 'space-between',
                    alignItems: 'center', marginBottom: '24px' }}>
        <div>
          <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 700 }}>Airdrop Campaigns</h2>
          <p style={{ margin: '4px 0 0', fontSize: '13px', color: '#888' }}>
            {campaigns.length} campaign{campaigns.length !== 1 ? 's' : ''} total
          </p>
        </div>
        <button
          onClick={onCreateNew}
          style={{ background: '#7C3AED', color: 'white', border: 'none',
                   borderRadius: '8px', padding: '10px 20px', cursor: 'pointer',
                   fontWeight: 600, fontSize: '14px' }}>
          + New Campaign
        </button>
      </div>

      {campaigns.length === 0 ? (
        <div style={{ background: '#1a1a1a', border: '1px solid #333', borderRadius: '12px',
                      padding: '48px', textAlign: 'center', color: '#666' }}>
          No campaigns yet.
          <br /><br />
          <button onClick={onCreateNew}
            style={{ color: '#7C3AED', background: 'none', border: 'none',
                     cursor: 'pointer', fontSize: '14px' }}>
            Create your first campaign →
          </button>
        </div>
      ) : (
        <div style={{ background: '#1a1a1a', border: '1px solid #333',
                      borderRadius: '12px', overflow: 'hidden' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
            <thead>
              <tr style={{ borderBottom: '1px solid #333', background: '#111' }}>
                {([
                  ['name',             'Campaign'],
                  ['status',           'Status'],
                  ['totalRecipients',  'Recipients'],
                  ['createdAt',        'Created'],
                ] as [SortKey, string][]).map(([key, label]) => (
                  <th key={key}
                    onClick={() => toggleSort(key)}
                    style={{ padding: '12px 16px', textAlign: 'left', color: '#888',
                             fontWeight: 600, cursor: 'pointer', userSelect: 'none' }}>
                    {label}<SortIcon k={key} />
                  </th>
                ))}
                <th style={{ padding: '12px 16px', color: '#888', fontWeight: 600 }}>
                  Progress
                </th>
                <th style={{ padding: '12px 16px', color: '#888', fontWeight: 600 }}>
                  Type
                </th>
              </tr>
            </thead>
            <tbody>
              {sorted.map(c => {
                const statusStyle = STATUS_COLORS[c.status] ?? STATUS_COLORS.Pending
                const progress    = c.totalRecipients > 0
                  ? Math.round((c.processedCount / c.totalRecipients) * 100)
                  : 0

                return (
                  <tr key={c.id}
                    onClick={() => onSelect?.(c.id)}
                    style={{ borderBottom: '1px solid #222', cursor: 'pointer',
                             transition: 'background 0.15s' }}
                    onMouseEnter={e => (e.currentTarget.style.background = '#222')}
                    onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}>

                    <td style={{ padding: '14px 16px' }}>
                      <div style={{ fontWeight: 600 }}>{c.name}</div>
                      <div style={{ color: '#666', fontSize: '11px', fontFamily: 'monospace', marginTop: '2px' }}>
                        {c.contractAddress.slice(0, 10)}...
                      </div>
                    </td>

                    <td style={{ padding: '14px 16px' }}>
                      <span style={{ background: statusStyle.bg, color: statusStyle.color,
                                     padding: '3px 10px', borderRadius: '20px',
                                     fontSize: '12px', fontWeight: 600 }}>
                        {c.status === 'InProgress' ? '⏳ ' : ''}
                        {c.status}
                      </span>
                    </td>

                    <td style={{ padding: '14px 16px', color: '#aaa' }}>
                      {c.processedCount} / {c.totalRecipients}
                    </td>

                    <td style={{ padding: '14px 16px', color: '#666', fontSize: '12px' }}>
                      {new Date(c.createdAt).toLocaleDateString()}
                    </td>

                    <td style={{ padding: '14px 16px', minWidth: '120px' }}>
                      <div style={{ background: '#333', borderRadius: '4px', height: '6px' }}>
                        <div style={{
                          background: c.status === 'Completed' ? '#22c55e'
                            : c.status === 'Failed' ? '#ef4444' : '#7C3AED',
                          width: `${progress}%`,
                          height: '100%', borderRadius: '4px',
                          transition: 'width 0.5s ease',
                        }} />
                      </div>
                      <div style={{ fontSize: '11px', color: '#666', marginTop: '3px' }}>
                        {progress}%
                      </div>
                    </td>

                    <td style={{ padding: '14px 16px' }}>
                      <span style={{ fontSize: '12px', color: '#888' }}>
                        {c.distributionType}
                      </span>
                      <span style={{ fontSize: '11px', color: '#555', display: 'block' }}>
                        {c.tokenType}
                      </span>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
