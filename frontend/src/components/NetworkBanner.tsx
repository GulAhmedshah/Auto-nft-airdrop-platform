// frontend/src/components/NetworkBanner.tsx
// ─────────────────────────────────────────────────────────────────────────────
// Shows a warning banner when the connected wallet is on an unsupported chain.
// Offers a one-click switch to Sepolia (testnet) or Mainnet.
// ─────────────────────────────────────────────────────────────────────────────

import { useAccount, useChainId, useSwitchChain } from 'wagmi'
import { sepolia }                                 from 'wagmi/chains'
import { isSupportedChain, CHAIN_NAMES }           from '../config/wagmi'

export function NetworkBanner() {
  const { isConnected }             = useAccount()
  const chainId                     = useChainId()
  const { switchChain, isPending }  = useSwitchChain()

  // Only show when wallet is connected AND on an unsupported chain
  if (!isConnected || isSupportedChain(chainId)) return null

  const currentName = CHAIN_NAMES[chainId] ?? `Chain ${chainId}`

  return (
    <div style={{
      position:        'fixed',
      top:             0,
      left:            0,
      right:           0,
      zIndex:          9999,
      background:      '#EF4444',
      color:           'white',
      padding:         '10px 20px',
      display:         'flex',
      alignItems:      'center',
      justifyContent:  'center',
      gap:             '12px',
      fontSize:        '14px',
      fontWeight:      500,
    }}>
      <span>
        ⚠️ <strong>{currentName}</strong> is not supported.
        Please switch to Ethereum, Polygon, Arbitrum, or Sepolia.
      </span>

      <button
        onClick={() => switchChain({ chainId: sepolia.id })}
        disabled={isPending}
        style={{
          background:    'white',
          color:         '#EF4444',
          border:        'none',
          borderRadius:  '6px',
          padding:       '4px 12px',
          cursor:        'pointer',
          fontWeight:    600,
          fontSize:      '13px',
        }}
      >
        {isPending ? 'Switching...' : 'Switch to Sepolia'}
      </button>
    </div>
  )
}
