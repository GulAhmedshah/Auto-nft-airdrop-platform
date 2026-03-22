// frontend/src/pages/user/Portfolio.tsx
import { useState }            from 'react'
import { useAccount, useChainId } from 'wagmi'
import { useNFTPortfolio }     from '../../hooks/useNFTPortfolio'
import { NFTCard }             from '../../components/NFTCard'
import { TransactionLink }     from '../../components/TransactionLink'
import { AirdropHistory }      from './AirdropHistory'

// ── Contract addresses to scan ────────────────────────────────────────────────
// In production: load from backend /api/collections
// For now: read from environment variables
const CONTRACTS = [
  {
    address: import.meta.env.VITE_NFT721_ADDRESS  ?? '',
    type:    'ERC721'  as const,
  },
  {
    address: import.meta.env.VITE_NFT1155_ADDRESS ?? '',
    type:    'ERC1155' as const,
    tokenIds: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  },
].filter(c => c.address !== '')

type Tab = 'nfts' | 'history'

export default function Portfolio() {
  const { address, isConnected } = useAccount()
  const chainId                  = useChainId()
  const [activeTab, setActiveTab] = useState<Tab>('nfts')

  const { nfts, isLoading, error, refresh, totalCount } =
    useNFTPortfolio(CONTRACTS)

  const erc721s  = nfts.filter(n => n.tokenType === 'ERC721')
  const erc1155s = nfts.filter(n => n.tokenType === 'ERC1155')

  if (!isConnected) {
    return (
      <div style={styles.page}>
        <div style={styles.empty}>
          Connect your wallet to view your NFT portfolio.
        </div>
      </div>
    )
  }

  return (
    <div style={styles.page}>

      {/* Header */}
      <div style={styles.header}>
        <div>
          <h2 style={styles.title}>My NFT Portfolio</h2>
          <p style={styles.address}>
            {address?.slice(0, 8)}...{address?.slice(-6)}
          </p>
        </div>
        <button onClick={refresh} style={styles.refreshBtn}
          disabled={isLoading}>
          {isLoading ? '⏳' : '↺'} Refresh
        </button>
      </div>

      {/* Stats row */}
      <div style={styles.statsRow}>
        {[
          { label: 'Total NFTs',      value: totalCount               },
          { label: 'ERC-721 Tokens',  value: erc721s.length          },
          { label: 'ERC-1155 Tokens', value: erc1155s.length         },
          { label: 'Collections',     value: new Set(nfts.map(n => n.contractAddress)).size },
        ].map(({ label, value }) => (
          <div key={label} style={styles.statCard}>
            <div style={styles.statValue}>{value}</div>
            <div style={styles.statLabel}>{label}</div>
          </div>
        ))}
      </div>

      {/* Tabs */}
      <div style={styles.tabs}>
        {(['nfts', 'history'] as Tab[]).map(tab => (
          <button key={tab} onClick={() => setActiveTab(tab)}
            style={styles.tab(activeTab === tab)}>
            {tab === 'nfts' ? '🖼️ My NFTs' : '📜 Airdrop History'}
          </button>
        ))}
      </div>

      {/* Tab content */}
      {activeTab === 'nfts' && (
        <>
          {error && (
            <div style={styles.error}>
              ⚠️ {error}
              <br />
              <span style={{ fontSize: '12px', color: '#888' }}>
                Make sure contract addresses are set in your .env file.
              </span>
            </div>
          )}

          {isLoading && (
            <div style={styles.loading}>Loading your NFTs...</div>
          )}

          {!isLoading && nfts.length === 0 && !error && (
            <div style={styles.empty}>
              <div style={{ fontSize: '48px', marginBottom: '16px' }}>🎨</div>
              <div>No NFTs found in your wallet yet.</div>
              <div style={{ fontSize: '13px', color: '#666', marginTop: '8px' }}>
                NFTs from airdrop campaigns will appear here.
              </div>
            </div>
          )}

          {/* ERC-721 grid */}
          {erc721s.length > 0 && (
            <div style={styles.section}>
              <div style={styles.sectionTitle}>ERC-721 Tokens ({erc721s.length})</div>
              <div style={styles.grid}>
                {erc721s.map(nft => (
                  <NFTCard
                    key={`${nft.contractAddress}-${nft.tokenId}`}
                    contractAddress={nft.contractAddress}
                    tokenId={nft.tokenId}
                    tokenURI={nft.tokenURI}
                    collectionName={nft.collectionName}
                    chainId={chainId}
                  />
                ))}
              </div>
            </div>
          )}

          {/* ERC-1155 grid */}
          {erc1155s.length > 0 && (
            <div style={styles.section}>
              <div style={styles.sectionTitle}>ERC-1155 Tokens ({erc1155s.length})</div>
              <div style={styles.grid}>
                {erc1155s.map(nft => (
                  <NFTCard
                    key={`${nft.contractAddress}-${nft.tokenId}`}
                    contractAddress={nft.contractAddress}
                    tokenId={nft.tokenId}
                    tokenURI={nft.tokenURI}
                    collectionName={nft.collectionName}
                    chainId={chainId}
                    balance={nft.balance}
                  />
                ))}
              </div>
            </div>
          )}
        </>
      )}

      {activeTab === 'history' && address && (
        <AirdropHistory address={address} chainId={chainId} />
      )}
    </div>
  )
}

// ── Styles ────────────────────────────────────────────────────────────────────
const styles = {
  page:         { padding: '32px', maxWidth: '960px', margin: '0 auto', color: '#fff', fontFamily: 'sans-serif' },
  header:       { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '24px' },
  title:        { margin: 0, fontSize: '24px', fontWeight: 700 },
  address:      { margin: '4px 0 0', fontSize: '13px', color: '#888', fontFamily: 'monospace' },
  refreshBtn:   { background: 'transparent', color: '#888', border: '1px solid #333', borderRadius: '8px',
                  padding: '8px 16px', cursor: 'pointer', fontSize: '13px' },
  statsRow:     { display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '12px', marginBottom: '24px' },
  statCard:     { background: '#1a1a1a', border: '1px solid #333', borderRadius: '10px',
                  padding: '16px', textAlign: 'center' as const },
  statValue:    { fontSize: '28px', fontWeight: 700, color: '#a78bfa' },
  statLabel:    { fontSize: '12px', color: '#666', marginTop: '4px' },
  tabs:         { display: 'flex', gap: '4px', marginBottom: '24px',
                  borderBottom: '1px solid #333', paddingBottom: '0' },
  tab:          (active: boolean) => ({
    background:   'none', border: 'none', cursor: 'pointer',
    padding:      '10px 20px', fontSize: '14px', fontWeight: active ? 600 : 400,
    color:        active ? '#fff' : '#666',
    borderBottom: active ? '2px solid #7C3AED' : '2px solid transparent',
    marginBottom: '-1px',
  }),
  section:      { marginBottom: '32px' },
  sectionTitle: { fontSize: '14px', fontWeight: 700, color: '#888',
                  textTransform: 'uppercase' as const, letterSpacing: '0.05em', marginBottom: '16px' },
  grid:         { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: '16px' },
  loading:      { textAlign: 'center' as const, color: '#888', padding: '48px' },
  error:        { background: '#ef444415', border: '1px solid #ef444430', borderRadius: '8px',
                  padding: '16px', color: '#fca5a5', fontSize: '13px', marginBottom: '16px' },
  empty:        { textAlign: 'center' as const, color: '#666', padding: '64px',
                  background: '#1a1a1a', border: '1px solid #333', borderRadius: '12px' },
} as const
