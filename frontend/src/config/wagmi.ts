// frontend/src/config/wagmi.ts
// ─────────────────────────────────────────────────────────────────────────────
// Wagmi + RainbowKit configuration
// Chains: mainnet, polygon, arbitrum, sepolia (testnet)
// ─────────────────────────────────────────────────────────────────────────────

import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { mainnet, polygon, arbitrum, sepolia } from 'wagmi/chains'

// Chain IDs we officially support — used for network detection banner
export const SUPPORTED_CHAIN_IDS = [
  mainnet.id,   // 1
  polygon.id,   // 137
  arbitrum.id,  // 42161
  sepolia.id,   // 11155111
] as const

export const SUPPORTED_CHAINS = [mainnet, polygon, arbitrum, sepolia] as const

// WalletConnect project ID — get one free at https://cloud.walletconnect.com
const projectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || 'demo-project-id'

/**
 * wagmiConfig — passed to both <WagmiProvider> and <RainbowKitProvider>.
 * getDefaultConfig sets  up the transports (RPC URLs) and connectors
 * (MetaMask, WalletConnect, Coinbase Wallet, Rainbow) automatically.
 */
export const wagmiConfig = getDefaultConfig({
  appName:     'NFT Airdrop Platform',
  projectId,
  chains:      SUPPORTED_CHAINS,
  ssr:         false,
})

// ── Helper — check if a chainId is supported ──────────────────────────────────
export function isSupportedChain(chainId: number | undefined): boolean {
  if (!chainId) return false
  return (SUPPORTED_CHAIN_IDS as readonly number[]).includes(chainId)
}

// ── Chain display names for the UI ───────────────────────────────────────────
export const CHAIN_NAMES: Record<number, string> = {
  1:        'Ethereum Mainnet',
  137:      'Polygon',
  42161:    'Arbitrum One',
  11155111: 'Sepolia Testnet',
}
