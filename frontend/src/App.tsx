// frontend/src/App.tsx
import { useState }              from 'react'
import { ConnectButton }         from '@rainbow-me/rainbowkit'
import { useAccount, useChainId,
         useWriteContract }      from 'wagmi'
import { useAuth }               from './hooks/useAuth'
import DeployWizard              from './pages/admin/DeployWizard'
import CampaignCreator           from './pages/admin/CampaignCreator'
import CampaignList              from './pages/admin/CampaignList'
import Portfolio                 from './pages/user/Portfolio'
import ClaimPage                 from './pages/user/ClaimPage'

// ── Paste your deployed NFT721 contract address here ─────────────────────────
const NFT721_CONTRACT = '0x42885db4003d6779c66bc2ad4f6dd85a78999c1a'

// Minimal ABI — just the mint function
const MINT_ABI = [
  {
    name: 'mint',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to',       type: 'address' },
      { name: 'quantity', type: 'uint256' },
    ],
    outputs: [],
  },
] as const

// ── MintTest component ────────────────────────────────────────────────────────
function MintTest() {
  const { address }            = useAccount()
  const chainId                = useChainId()
  const { writeContractAsync } = useWriteContract()
  const [status, setStatus]    = useState('')
  const [loading, setLoading]  = useState(false)

  async function mint() {
    if (!address) return
    setLoading(true)
    setStatus('Waiting for signature...')
    try {
      const hash = await writeContractAsync({
        address:      NFT721_CONTRACT as `0x${string}`,
        abi:          MINT_ABI,
        functionName: 'mint',
        args:         [address as `0x${string}`, 1n],
      })
      setStatus(`✅ Minted! Tx: ${hash.slice(0, 12)}...`)
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed'
      setStatus(msg.includes('rejected') ? '❌ Rejected by user' : `❌ ${msg.slice(0, 80)}`)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{
      background: '#1a1a1a', border: '1px solid #333', borderRadius: '12px',
      padding: '20px', maxWidth: '360px', margin: '0 auto',
    }}>
      <div style={{ fontSize: '14px', fontWeight: 700, marginBottom: '12px', color: '#fff' }}>
        🎨 Mint Test NFT
      </div>
      <div style={{ fontSize: '12px', color: '#666', marginBottom: '12px' }}>
        Contract: {NFT721_CONTRACT.slice(0, 10)}...
        <br />
        Network: {chainId === 11155111 ? 'Sepolia ✅' : '⚠️ Switch to Sepolia'}
      </div>
      <button
        onClick={mint}
        disabled={loading || chainId !== 11155111}
        style={{
          background:   loading ? '#333' : '#22c55e',
          color:        'white',
          border:       'none',
          borderRadius: '8px',
          padding:      '10px 20px',
          cursor:       loading ? 'not-allowed' : 'pointer',
          fontWeight:   600,
          fontSize:     '14px',
          width:        '100%',
        }}
      >
        {loading ? 'Minting...' : 'Mint 1 NFT to My Wallet'}
      </button>
      {status && (
        <p style={{ marginTop: '10px', fontSize: '13px',
                    color: status.includes('✅') ? '#22c55e' : '#ef4444' }}>
          {status}
        </p>
      )}
    </div>
  )
}

// ── Main App ──────────────────────────────────────────────────────────────────
export default function App() {
  const { address, isConnected } = useAccount()
  const {
    isAuthenticated, isLoading, error, signIn, signOut,
  } = useAuth()

  return (
    <div style={{
      minHeight: '100vh', background: '#0f0f0f', color: '#fff',
      fontFamily: 'sans-serif',
    }}>

      {/* Top bar */}
      <div style={{
        padding: '16px 32px', borderBottom: '1px solid #222',
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      }}>
        <div style={{ fontSize: '18px', fontWeight: 700 }}>
          🚀 NFT Airdrop Platform
        </div>
        <ConnectButton />
      </div>

      {/* Main content */}
      <div style={{ padding: '32px', maxWidth: '1200px', margin: '0 auto' }}>

        {/* Auth section */}
        {isConnected && !isAuthenticated && (
          <div style={{
            background: '#1a1a1a', border: '1px solid #333', borderRadius: '12px',
            padding: '24px', maxWidth: '360px', margin: '0 auto 32px',
            textAlign: 'center',
          }}>
            <p style={{ color: '#888', fontSize: '14px', marginBottom: '16px' }}>
              Connected: {address?.slice(0, 6)}...{address?.slice(-4)}
            </p>
            {error && <p style={{ color: '#ef4444', fontSize: '13px', marginBottom: '12px' }}>{error}</p>}
            <button
              onClick={signIn} disabled={isLoading}
              style={{
                background: '#7C3AED', color: 'white', border: 'none',
                borderRadius: '8px', padding: '12px 24px', cursor: 'pointer',
                fontWeight: 600, fontSize: '14px', width: '100%',
              }}
            >
              {isLoading ? 'Signing...' : 'Sign In With Ethereum'}
            </button>
          </div>
        )}

        {isAuthenticated && (
          <>
            {/* Sign out bar */}
            <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: '24px' }}>
              <span style={{ color: '#888', fontSize: '13px', marginRight: '12px' }}>
                ✓ {address?.slice(0, 6)}...{address?.slice(-4)}
              </span>
              <button onClick={signOut} style={{
                background: 'transparent', color: '#ef4444',
                border: '1px solid #ef4444', borderRadius: '6px',
                padding: '4px 12px', cursor: 'pointer', fontSize: '13px',
              }}>
                Sign Out
              </button>
            </div>

            {/* Mint Test Section */}
            <div style={{ marginBottom: '40px' }}>
              <h3 style={{ fontSize: '16px', color: '#888', marginBottom: '16px',
                           textAlign: 'center' }}>
                — Test: Mint an NFT to your wallet —
              </h3>
              <MintTest />
            </div>

            {/* Portfolio */}
            <Portfolio />

            {/* Claim Page */}
            <ClaimPage />

            {/* Admin: Campaign List */}
            <CampaignList />

            {/* Admin: Campaign Creator */}
            <CampaignCreator />

            {/* Admin: Deploy Wizard */}
            <DeployWizard />
          </>
        )}

      </div>
    </div>
  )
}
