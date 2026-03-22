// frontend/src/pages/user/AirdropHistory.tsx
import { useState, useEffect } from 'react'
import { usePublicClient }     from 'wagmi'
import { TransactionLink }     from '../../components/TransactionLink'

interface AirdropEvent {
  txHash:          string
  contractAddress: string
  tokenId?:        number
  amount:          number
  blockNumber:     bigint
  timestamp?:      number
}

interface Props {
  address: string
  chainId: number
}

// Transfer event topics
const TRANSFER_TOPIC      = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'
const TRANSFER_SINGLE_TOPIC = '0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62'

export function AirdropHistory({ address, chainId }: Props) {
  const publicClient = usePublicClient()
  const [events,    setEvents]    = useState<AirdropEvent[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [error,     setError]     = useState<string | null>(null)

  useEffect(() => {
    if (address && publicClient) fetchHistory()
  }, [address, publicClient])

  async function fetchHistory() {
    setIsLoading(true)
    setError(null)

    try {
      const paddedAddress = `0x${address.slice(2).padStart(64, '0').toLowerCase()}`
      const result: AirdropEvent[] = []

      // Fetch ERC-721 Transfer events where user is recipient (topic[2])
      try {
        const erc721Logs = await publicClient!.getLogs({
          event: {
            type:   'event',
            name:   'Transfer',
            inputs: [
              { type: 'address', name: 'from',    indexed: true },
              { type: 'address', name: 'to',      indexed: true },
              { type: 'uint256', name: 'tokenId', indexed: true },
            ],
          },
          args:        { to: address as `0x${string}` },
          fromBlock:   'earliest',
          toBlock:     'latest',
        })

        for (const log of erc721Logs.slice(-50)) { // last 50
          result.push({
            txHash:          log.transactionHash ?? '',
            contractAddress: log.address,
            tokenId:         log.args?.tokenId !== undefined
              ? Number(log.args.tokenId as bigint) : undefined,
            amount:          1,
            blockNumber:     log.blockNumber ?? 0n,
          })
        }
      } catch {
        // getLogs may fail on some networks — skip silently
      }

      // Sort by block number descending (newest first)
      result.sort((a, b) => Number(b.blockNumber - a.blockNumber))

      setEvents(result)
    } catch (err) {
      setError('Failed to load airdrop history. The RPC may not support event queries.')
    } finally {
      setIsLoading(false)
    }
  }

  if (isLoading) return (
    <div style={{ textAlign: 'center', color: '#888', padding: '48px' }}>
      Loading airdrop history...
    </div>
  )

  if (error) return (
    <div style={{ background: '#ef444415', border: '1px solid #ef444430',
                  borderRadius: '8px', padding: '16px', color: '#fca5a5', fontSize: '13px' }}>
      {error}
    </div>
  )

  if (events.length === 0) return (
    <div style={{ textAlign: 'center', color: '#666', padding: '64px',
                  background: '#1a1a1a', border: '1px solid #333', borderRadius: '12px' }}>
      <div style={{ fontSize: '48px', marginBottom: '16px' }}>📭</div>
      <div>No airdrop history found.</div>
      <div style={{ fontSize: '13px', marginTop: '8px' }}>
        NFTs received via airdrops will appear here.
      </div>
    </div>
  )

  return (
    <div>
      <div style={{ fontSize: '13px', color: '#888', marginBottom: '16px' }}>
        {events.length} transfer{events.length !== 1 ? 's' : ''} found
      </div>

      <div style={{ background: '#1a1a1a', border: '1px solid #333',
                    borderRadius: '12px', overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
          <thead>
            <tr style={{ borderBottom: '1px solid #333', background: '#111' }}>
              {['Contract', 'Token ID', 'Amount', 'Block', 'Tx Hash'].map(h => (
                <th key={h} style={{ padding: '12px 16px', textAlign: 'left',
                                     color: '#888', fontWeight: 600 }}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {events.map((event, i) => (
              <tr key={i} style={{ borderBottom: '1px solid #222' }}>
                <td style={{ padding: '12px 16px' }}>
                  <TransactionLink
                    hash={event.contractAddress}
                    chainId={chainId}
                    type="token"
                  />
                </td>
                <td style={{ padding: '12px 16px', color: '#aaa' }}>
                  {event.tokenId !== undefined ? `#${event.tokenId}` : '—'}
                </td>
                <td style={{ padding: '12px 16px', color: '#22c55e' }}>
                  +{event.amount}
                </td>
                <td style={{ padding: '12px 16px', color: '#666', fontFamily: 'monospace' }}>
                  {event.blockNumber.toString()}
                </td>
                <td style={{ padding: '12px 16px' }}>
                  <TransactionLink hash={event.txHash} chainId={chainId} type="tx" />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
