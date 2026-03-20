// frontend/src/providers/WalletProvider.tsx
// ─────────────────────────────────────────────────────────────────────────────
// Root provider that wraps the entire app.
// Order matters: QueryClientProvider → WagmiProvider → RainbowKitProvider
//
// Why this order?
//   • QueryClientProvider must be outermost — wagmi hooks use react-query
//     internally, so the QueryClient must exist before WagmiProvider mounts.
//   • WagmiProvider must wrap RainbowKitProvider — RainbowKit reads wallet
//     state from wagmi's context.
// ─────────────────────────────────────────────────────────────────────────────

import { ReactNode }           from 'react'
import { WagmiProvider }       from 'wagmi'
import { RainbowKitProvider,
         darkTheme }           from '@rainbow-me/rainbowkit'
import { QueryClient,
         QueryClientProvider } from '@tanstack/react-query'

import { wagmiConfig }         from '../config/wagmi'
import { NetworkBanner }       from '../components/NetworkBanner'

import '@rainbow-me/rainbowkit/styles.css'

// ── QueryClient — shared across the whole app ─────────────────────────────────
// staleTime: 30s — wagmi contract reads won't refetch within 30 seconds
// gcTime:    5min — cached data kept 5 minutes after component unmounts
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime:          30_000,
      gcTime:             5 * 60 * 1000,
      retry:              2,
      refetchOnWindowFocus: false,
    },
  },
})

interface WalletProviderProps {
  children: ReactNode
}

/**
 * WalletProvider
 * Wrap your <App /> with this in main.tsx:
 *
 *   <WalletProvider>
 *     <App />
 *   </WalletProvider>
 */
export function WalletProvider({ children }: WalletProviderProps) {
  return (
    <QueryClientProvider client={queryClient}>
      <WagmiProvider config={wagmiConfig}>
        <RainbowKitProvider
          theme={darkTheme({
            accentColor:          '#7C3AED', // purple — matches platform brand
            accentColorForeground: 'white',
            borderRadius:          'medium',
          })}
          modalSize="compact"
        >
          {/* Network mismatch banner — shown when user is on unsupported chain */}
          <NetworkBanner />
          {children}
        </RainbowKitProvider>
      </WagmiProvider>
    </QueryClientProvider>
  )
}
