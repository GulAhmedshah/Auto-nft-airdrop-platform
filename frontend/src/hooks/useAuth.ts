// frontend/src/hooks/useAuth.ts
import { useState, useEffect, useCallback } from 'react'
import { useAccount, useChainId, useSignMessage } from 'wagmi'
import axios from 'axios'

const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001'

export interface AuthState {
  address:         string | undefined
  isConnected:     boolean
  isAuthenticated: boolean
  isLoading:       boolean
  error:           string | null
  signIn:          () => Promise<void>
  signOut:         () => Promise<void>
}

// Build EIP-4361 SIWE message manually — no siwe package needed on frontend
function buildSiweMessage(params: {
  domain:  string
  address: string
  uri:     string
  chainId: number
  nonce:   string
}): string {
  const now = new Date().toISOString()
  return [
    `${params.domain} wants you to sign in with your Ethereum account:`,
    params.address,
    '',
    'Sign in to NFT Airdrop Platform.',
    '',
    `URI: ${params.uri}`,
    'Version: 1',
    `Chain ID: ${params.chainId}`,
    `Nonce: ${params.nonce}`,
    `Issued At: ${now}`,
  ].join('\n')
}

export function useAuth(): AuthState {
  const { address, isConnected } = useAccount()
  const chainId                  = useChainId()
  const { signMessageAsync }     = useSignMessage()

  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isLoading,       setIsLoading]       = useState(false)
  const [error,           setError]           = useState<string | null>(null)

  useEffect(() => { checkSession() }, [])

  useEffect(() => {
    if (isAuthenticated) {
      setIsAuthenticated(false)
      setError(null)
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [address, chainId])

  const checkSession = useCallback(async () => {
    try {
      const res = await axios.get(`${API_BASE}/api/auth/session`, {
        withCredentials: true,
      })
      if (res.data?.authenticated) setIsAuthenticated(true)
    } catch {
      setIsAuthenticated(false)
    }
  }, [])

  const signIn = useCallback(async () => {
    if (!address || !isConnected) {
      setError('Please connect your wallet first.')
      return
    }
    setIsLoading(true)
    setError(null)
    try {
      const { data } = await axios.get(`${API_BASE}/api/auth/nonce`, {
        withCredentials: true,
      })

      const message = buildSiweMessage({
        domain:  window.location.host,
        address,
        uri:     window.location.origin,
        chainId,
        nonce:   data.nonce,
      })

      const signature = await signMessageAsync({ message })

      await axios.post(
        `${API_BASE}/api/auth/verify`,
        { message, signature },
        { withCredentials: true }
      )

      setIsAuthenticated(true)
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Authentication failed'
      setError(msg.includes('rejected') ? 'Signature rejected.' : msg)
      setIsAuthenticated(false)
    } finally {
      setIsLoading(false)
    }
  }, [address, isConnected, chainId, signMessageAsync])

  const signOut = useCallback(async () => {
    setIsLoading(true)
    try {
      await axios.delete(`${API_BASE}/api/auth/session`, { withCredentials: true })
    } finally {
      setIsAuthenticated(false)
      setIsLoading(false)
      setError(null)
    }
  }, [])

  return { address, isConnected, isAuthenticated, isLoading, error, signIn, signOut }
}
