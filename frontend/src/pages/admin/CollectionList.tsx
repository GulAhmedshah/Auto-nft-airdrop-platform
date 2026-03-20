// frontend/src/pages/admin/CollectionList.tsx
import { useState, useEffect } from 'react'
import axios                   from 'axios'

const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001'

interface Collection {
  id:              string
  contractAddress: string
  tokenType:       'ERC721' | 'ERC1155'
  name:            string
  symbol:          string
  chainId:         number
  txHash:          string
  deployedAt:      string
}

const CHAIN_NAMES: Record<number, string> = {
  1: 'Mainnet', 137: 'Polygon', 42161: 'Arbitrum', 11155111: 'Sepolia',
}

const EXPLORER: Record<number, string> = {
  1: 'https://etherscan.io', 137: 'https://polygonscan.com',
  42161: 'https://arbiscan.io', 11155111: 'https://sepolia.etherscan.io',
}

export default function CollectionList() {
  const [collections, setCollections] = useState<Collection[]>([])
  const [loading,     setLoading]     = useState(true)
  const [error,       setError]       = useState<string | null>(null)

  useEffect(() => {
    fetchCollections()
  }, [])

  async function fetchCollections() {
    setLoading(true)
    try {
      const res = await axios.get(`${API_BASE}/api/collections`, {
        withCredentials: true,
      })
      setCollections(res.data)
    } catch {
      setError('Failed to load collections.')
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <div style={{ color: '#888', padding: '24px' }}>Loading collections...</div>
  if (error)   return <div style={{ color: '#ef4444', padding: '24px' }}>{error}</div>

  return (
    <div style={{ padding: '32px', maxWidth: '900px', margin: '0 auto', color: '#fff', fontFamily: 'sans-serif' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
        <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 700 }}>Deployed Collections</h2>
        <a href="/admin/deploy" style={{
          background: '#7C3AED', color: 'white', padding: '10px 20px',
          borderRadius: '8px', textDecoration: 'none', fontSize: '14px', fontWeight: 600,
        }}>
          + Deploy New
        </a>
      </div>

      {collections.length === 0 ? (
        <div style={{ background: '#1a1a1a', border: '1px solid #333', borderRadius: '12px',
                      padding: '48px', textAlign: 'center', color: '#666' }}>
          No collections deployed yet.
          <br /><br />
          <a href="/admin/deploy" style={{ color: '#7C3AED' }}>Deploy your first collection →</a>
        </div>
      ) : (
        <div style={{ background: '#1a1a1a', border: '1px solid #333', borderRadius: '12px', overflow: 'hidden' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
            <thead>
              <tr style={{ borderBottom: '1px solid #333', background: '#111' }}>
                {['Name', 'Type', 'Address', 'Chain', 'Deployed'].map(h => (
                  <th key={h} style={{ padding: '12px 16px', textAlign: 'left', color: '#888', fontWeight: 600 }}>
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {collections.map(c => (
                <tr key={c.id} style={{ borderBottom: '1px solid #222' }}>
                  <td style={{ padding: '12px 16px' }}>
                    <div style={{ fontWeight: 600 }}>{c.name}</div>
                    <div style={{ color: '#888', fontSize: '12px' }}>{c.symbol}</div>
                  </td>
                  <td style={{ padding: '12px 16px' }}>
                    <span style={{
                      background: c.tokenType === 'ERC721' ? '#7C3AED20' : '#0ea5e920',
                      color:      c.tokenType === 'ERC721' ? '#a78bfa'   : '#38bdf8',
                      padding: '3px 8px', borderRadius: '4px', fontSize: '12px', fontWeight: 600,
                    }}>
                      {c.tokenType}
                    </span>
                  </td>
                  <td style={{ padding: '12px 16px' }}>
                    <a
                      href={`${EXPLORER[c.chainId] ?? EXPLORER[11155111]}/address/${c.contractAddress}`}
                      target="_blank" rel="noopener noreferrer"
                      style={{ color: '#7C3AED', fontFamily: 'monospace' }}
                    >
                      {c.contractAddress.slice(0, 8)}...{c.contractAddress.slice(-6)} ↗
                    </a>
                  </td>
                  <td style={{ padding: '12px 16px', color: '#aaa' }}>
                    {CHAIN_NAMES[c.chainId] ?? `Chain ${c.chainId}`}
                  </td>
                  <td style={{ padding: '12px 16px', color: '#666', fontSize: '12px' }}>
                    {new Date(c.deployedAt).toLocaleDateString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
