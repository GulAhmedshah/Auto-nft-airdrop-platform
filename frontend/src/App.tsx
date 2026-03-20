// frontend/src/App.tsx
// ─────────────────────────────────────────────────────────────────────────────
// Root app component — demonstrates wallet connection + SIWE auth flow.
// In Phase 2 modules this becomes a proper router with pages.
// ─────────────────────────────────────────────────────────────────────────────

import { ConnectButton } from '@rainbow-me/rainbowkit'
import { useAuth }       from './hooks/useAuth'
import DeployWizard from './pages/admin/DeployWizard'
import CampaignCreator from './pages/admin/CampaignCreator'
import CampaignList    from './pages/admin/CampaignList'

export default function App() {
  const {
    address,
    isConnected,
    isAuthenticated,
    isLoading,
    error,
    signIn,
    signOut,
  } = useAuth()

  return (
    <div style={{
      minHeight:      '100vh',
      display:        'flex',
      flexDirection:  'column',
      alignItems:     'center',
      justifyContent: 'center',
      gap:            '24px',
      background:     '#0f0f0f',
      color:          'white',
      fontFamily:     'sans-serif',
    }}>
      <h1 style={{ fontSize: '28px', fontWeight: 700, margin: 0 }}>
        NFT Airdrop Platform
      </h1>

      {/* RainbowKit connect button — handles MetaMask, WalletConnect, etc. */}
      <ConnectButton />

      {/* Auth section — shown only when wallet is connected */}
      {isConnected && (
        <div style={{
          background:   '#1a1a1a',
          border:       '1px solid #333',
          borderRadius: '12px',
          padding:      '24px',
          width:        '360px',
          display:      'flex',
          flexDirection:'column',
          gap:          '12px',
        }}>
          <p style={{ margin: 0, fontSize: '13px', color: '#888' }}>
            Connected: <span style={{ color: '#fff' }}>
              {address?.slice(0, 6)}...{address?.slice(-4)}
            </span>
          </p>

          <p style={{ margin: 0, fontSize: '13px', color: '#888' }}>
            Auth status:{' '}
            <span style={{ color: isAuthenticated ? '#22c55e' : '#ef4444' }}>
              {isAuthenticated ? '✓ Authenticated' : '✗ Not signed in'}
            </span>
          </p>

          {error && (
            <p style={{ margin: 0, fontSize: '13px', color: '#ef4444' }}>
              {error}
            </p>
          )}

          {!isAuthenticated ? (
            <button
              onClick={signIn}
              disabled={isLoading}
              style={{
                background:   '#7C3AED',
                color:        'white',
                border:       'none',
                borderRadius: '8px',
                padding:      '10px',
                cursor:       'pointer',
                fontWeight:   600,
                fontSize:     '14px',
                opacity:      isLoading ? 0.7 : 1,
              }}
            >
              {isLoading ? 'Signing...' : 'Sign In With Ethereum'}
            </button>
          ) : (
            <button
              onClick={signOut}
              disabled={isLoading}
              style={{
                background:   'transparent',
                color:        '#ef4444',
                border:       '1px solid #ef4444',
                borderRadius: '8px',
                padding:      '10px',
                cursor:       'pointer',
                fontWeight:   600,
                fontSize:     '14px',
              }}
            >
              Sign Out
            </button>
          )}
        </div>

        
      )}
      {isAuthenticated && <DeployWizard />} 
      {isAuthenticated && <CampaignList />}
{isAuthenticated && <CampaignCreator />}
    </div>


  )
}
