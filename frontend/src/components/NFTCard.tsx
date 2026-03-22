// frontend/src/components/NFTCard.tsx
import { useState, useEffect } from 'react'
import { TransactionLink }     from './TransactionLink'

interface NFTMetadata {
  name?:        string
  description?: string
  image?:       string
}

interface Props {
  contractAddress: string
  tokenId:         number | bigint
  tokenURI?:       string
  collectionName?: string
  chainId?:        number
  balance?:        number  // for ERC-1155
}

// Convert IPFS URI to HTTP gateway URL
function ipfsToHttp(uri: string): string {
  if (!uri) return ''
  if (uri.startsWith('ipfs://')) {
    return uri.replace('ipfs://', 'https://ipfs.io/ipfs/')
  }
  return uri
}

export function NFTCard({
  contractAddress,
  tokenId,
  tokenURI,
  collectionName,
  chainId = 11155111,
  balance,
}: Props) {
  const [metadata, setMetadata] = useState<NFTMetadata | null>(null)
  const [loading,  setLoading]  = useState(false)
  const [imgError, setImgError] = useState(false)

  useEffect(() => {
    if (!tokenURI) return
    fetchMetadata()
  }, [tokenURI])

  async function fetchMetadata() {
    if (!tokenURI) return
    setLoading(true)
    try {
      const url = ipfsToHttp(tokenURI)
      const res = await fetch(url)
      const data: NFTMetadata = await res.json()
      setMetadata(data)
    } catch {
      // Metadata fetch failed — show placeholder
    } finally {
      setLoading(false)
    }
  }

  const imageUrl = metadata?.image ? ipfsToHttp(metadata.image) : null
  const tokenIdDisplay = tokenId.toString()

  return (
    <div style={{
      background:   '#1a1a1a',
      border:       '1px solid #333',
      borderRadius: '12px',
      overflow:     'hidden',
      transition:   'border-color 0.2s',
      cursor:       'default',
    }}
      onMouseEnter={e => (e.currentTarget.style.borderColor = '#7C3AED')}
      onMouseLeave={e => (e.currentTarget.style.borderColor = '#333')}
    >
      {/* Image area */}
      <div style={{
        width:      '100%',
        aspectRatio: '1',
        background:  '#111',
        display:     'flex',
        alignItems:  'center',
        justifyContent: 'center',
        overflow:    'hidden',
      }}>
        {loading ? (
          <div style={{ color: '#444', fontSize: '12px' }}>Loading...</div>
        ) : imageUrl && !imgError ? (
          <img
            src={imageUrl}
            alt={metadata?.name ?? `Token #${tokenIdDisplay}`}
            style={{ width: '100%', height: '100%', objectFit: 'cover' }}
            onError={() => setImgError(true)}
          />
        ) : (
          <div style={{
            fontSize: '40px',
            color:    '#333',
            display:  'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: '8px',
          }}>
            🖼️
            <span style={{ fontSize: '11px', color: '#555' }}>
              #{tokenIdDisplay}
            </span>
          </div>
        )}
      </div>

      {/* Info area */}
      <div style={{ padding: '12px' }}>
        <div style={{ fontWeight: 700, fontSize: '14px', marginBottom: '2px',
                      whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {metadata?.name ?? `Token #${tokenIdDisplay}`}
        </div>

        {collectionName && (
          <div style={{ fontSize: '12px', color: '#888', marginBottom: '8px' }}>
            {collectionName}
          </div>
        )}

        {balance !== undefined && balance > 1 && (
          <div style={{ fontSize: '12px', color: '#a78bfa', marginBottom: '6px' }}>
            Balance: {balance}
          </div>
        )}

        <TransactionLink
          hash={contractAddress}
          chainId={chainId}
          type="token"
          label={`${contractAddress.slice(0, 6)}...`}
        />
      </div>
    </div>
  )
}
