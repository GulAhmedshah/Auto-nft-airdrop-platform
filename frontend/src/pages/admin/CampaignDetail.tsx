// frontend/src/pages/admin/CampaignDetail.tsx
import { useAirdropJob } from '../../hooks/useAirdropJob'

const EXPLORER: Record<number, string> = {
  1: 'https://etherscan.io', 137: 'https://polygonscan.com',
  42161: 'https://arbiscan.io', 11155111: 'https://sepolia.etherscan.io',
}

const STATUS_COLORS: Record<string, string> = {
  Pending: '#f59e0b', InProgress: '#60a5fa', Completed: '#22c55e', Failed: '#ef4444',
}

interface Props {
  campaignId: string
  chainId?:   number
  onBack?:    () => void
}

export default function CampaignDetail({ campaignId, chainId = 11155111, onBack }: Props) {
  const { campaign, isLoading, isPolling, error, refresh } = useAirdropJob(campaignId)
  const explorer = EXPLORER[chainId] ?? EXPLORER[11155111]

  if (isLoading && !campaign) return (
    <div style={{ padding: '32px', color: '#888', fontFamily: 'sans-serif' }}>
      Loading campaign...
    </div>
  )

  if (error) return (
    <div style={{ padding: '32px', color: '#ef4444', fontFamily: 'sans-serif' }}>{error}</div>
  )

  if (!campaign) return null

  const statusColor = STATUS_COLORS[campaign.status] ?? '#888'
  const progress    = campaign.totalRecipients > 0
    ? Math.round((campaign.processedCount / campaign.totalRecipients) * 100)
    : 0

  return (
    <div style={{ padding: '32px', maxWidth: '800px', margin: '0 auto',
                  color: '#fff', fontFamily: 'sans-serif' }}>

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '24px' }}>
        {onBack && (
          <button onClick={onBack}
            style={{ background: 'none', border: '1px solid #333', color: '#888',
                     borderRadius: '8px', padding: '6px 12px', cursor: 'pointer' }}>
            ← Back
          </button>
        )}
        <div>
          <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 700 }}>{campaign.name}</h2>
          <p style={{ margin: '2px 0 0', fontSize: '13px', color: '#666' }}>
            Campaign ID: {campaign.id}
          </p>
        </div>
        {isPolling && (
          <span style={{ marginLeft: 'auto', fontSize: '12px', color: '#888' }}>
            ⏳ Live updates...
          </span>
        )}
      </div>

      {/* Status card */}
      <div style={{ background: '#1a1a1a', border: `1px solid ${statusColor}40`,
                    borderRadius: '12px', padding: '20px', marginBottom: '16px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <span style={{ background: `${statusColor}20`, color: statusColor,
                           padding: '4px 12px', borderRadius: '20px', fontSize: '13px', fontWeight: 700 }}>
              {campaign.status}
            </span>
            <div style={{ marginTop: '12px', fontSize: '14px', color: '#aaa' }}>
              {campaign.processedCount} of {campaign.totalRecipients} recipients processed
            </div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontSize: '36px', fontWeight: 700, color: statusColor }}>
              {progress}%
            </div>
            <div style={{ fontSize: '12px', color: '#666' }}>complete</div>
          </div>
        </div>

        {/* Progress bar */}
        <div style={{ background: '#333', borderRadius: '6px', height: '8px', marginTop: '16px' }}>
          <div style={{
            background: campaign.status === 'Failed' ? '#ef4444' : '#7C3AED',
            width: `${progress}%`, height: '100%', borderRadius: '6px',
            transition: 'width 0.5s ease',
          }} />
        </div>
      </div>

      {/* Details grid */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', marginBottom: '16px' }}>
        {[
          { label: 'Token Type',    value: campaign.tokenType },
          { label: 'Distribution',  value: campaign.distributionType },
          { label: 'Total Recipients', value: campaign.totalRecipients },
          { label: 'Created',       value: new Date(campaign.createdAt).toLocaleString() },
          { label: 'Scheduled At',  value: campaign.scheduledAt
              ? new Date(campaign.scheduledAt).toLocaleString() : 'Immediate' },
          { label: 'Executed At',   value: campaign.executedAt
              ? new Date(campaign.executedAt).toLocaleString() : '—' },
        ].map(({ label, value }) => (
          <div key={label} style={{ background: '#1a1a1a', border: '1px solid #333',
                                     borderRadius: '8px', padding: '14px' }}>
            <div style={{ fontSize: '11px', color: '#666', marginBottom: '4px',
                          textTransform: 'uppercase', letterSpacing: '0.05em' }}>
              {label}
            </div>
            <div style={{ fontSize: '14px', color: '#fff' }}>{value}</div>
          </div>
        ))}
      </div>

      {/* Contract address */}
      <div style={{ background: '#1a1a1a', border: '1px solid #333',
                    borderRadius: '12px', padding: '16px', marginBottom: '16px' }}>
        <div style={{ fontSize: '12px', color: '#666', marginBottom: '6px' }}>CONTRACT</div>
        <a href={`${explorer}/address/${campaign.contractAddress}`}
          target="_blank" rel="noopener noreferrer"
          style={{ color: '#7C3AED', fontFamily: 'monospace', fontSize: '13px' }}>
          {campaign.contractAddress} ↗
        </a>
      </div>

      {/* Merkle root */}
      {campaign.merkleRoot && (
        <div style={{ background: '#1a1a1a', border: '1px solid #333',
                      borderRadius: '12px', padding: '16px', marginBottom: '16px' }}>
          <div style={{ fontSize: '12px', color: '#666', marginBottom: '6px' }}>MERKLE ROOT</div>
          <div style={{ fontFamily: 'monospace', fontSize: '12px', color: '#a78bfa',
                        wordBreak: 'break-all' }}>
            {campaign.merkleRoot}
          </div>
        </div>
      )}

      {/* Transaction hashes */}
      {campaign.txHashes && campaign.txHashes.length > 0 && (
        <div style={{ background: '#1a1a1a', border: '1px solid #333',
                      borderRadius: '12px', padding: '16px', marginBottom: '16px' }}>
          <div style={{ fontSize: '12px', color: '#666', marginBottom: '10px' }}>
            TRANSACTIONS ({campaign.txHashes.length})
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
            {campaign.txHashes.map((hash, i) => (
              <a key={i}
                href={`${explorer}/tx/${hash}`}
                target="_blank" rel="noopener noreferrer"
                style={{ color: '#7C3AED', fontFamily: 'monospace', fontSize: '12px' }}>
                {hash.slice(0, 20)}...{hash.slice(-8)} ↗
              </a>
            ))}
          </div>
        </div>
      )}

      {/* Gas analytics */}
      {campaign.gasUsed && (
        <div style={{ background: '#1a1a1a', border: '1px solid #333',
                      borderRadius: '12px', padding: '16px', marginBottom: '16px' }}>
          <div style={{ fontSize: '12px', color: '#666', marginBottom: '10px' }}>
            GAS ANALYTICS
          </div>
          <div style={{ display: 'flex', gap: '24px' }}>
            <div>
              <div style={{ fontSize: '20px', fontWeight: 700, color: '#a78bfa' }}>
                {campaign.gasUsed.toLocaleString()}
              </div>
              <div style={{ fontSize: '12px', color: '#666' }}>Total Gas Used</div>
            </div>
            {campaign.totalRecipients > 0 && (
              <div>
                <div style={{ fontSize: '20px', fontWeight: 700, color: '#a78bfa' }}>
                  {Math.round(campaign.gasUsed / campaign.totalRecipients).toLocaleString()}
                </div>
                <div style={{ fontSize: '12px', color: '#666' }}>Gas Per Recipient</div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Error message */}
      {campaign.errorMessage && (
        <div style={{ background: '#ef444410', border: '1px solid #ef444430',
                      borderRadius: '12px', padding: '16px' }}>
          <div style={{ fontSize: '12px', color: '#ef4444', marginBottom: '6px', fontWeight: 700 }}>
            ERROR
          </div>
          <div style={{ fontSize: '13px', color: '#fca5a5' }}>{campaign.errorMessage}</div>
        </div>
      )}

      {/* Refresh button for completed/failed */}
      {(campaign.status === 'Completed' || campaign.status === 'Failed') && (
        <button onClick={refresh}
          style={{ marginTop: '16px', background: 'transparent', color: '#888',
                   border: '1px solid #333', borderRadius: '8px', padding: '8px 16px',
                   cursor: 'pointer', fontSize: '13px' }}>
          ↺ Refresh
        </button>
      )}
    </div>
  )
}
