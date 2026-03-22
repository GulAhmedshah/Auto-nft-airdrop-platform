// frontend/src/hooks/useNFTPortfolio.ts
// ─────────────────────────────────────────────────────────────────────────────
// useNFTPortfolio — fetches all NFTs owned by the connected wallet
//
// ── How it works ─────────────────────────────────────────────────────────────
//
//   For ERC-721:
//     1. Call balanceOf(address) → how many tokens owned
//     2. Call tokenOfOwnerByIndex(address, i) for each index → get token IDs
//     3. Call tokenURI(tokenId) for each token → get metadata URI
//
//   For ERC-1155:
//     1. We know token IDs from our deployed collections
//     2. Call balanceOf(address, tokenId) for each known ID
//     3. Call uri(tokenId) for metadata URI
//
//   Multicall: batch all these calls into one RPC request — much faster
//   than making individual calls (avoids N round trips).
// ─────────────────────────────────────────────────────────────────────────────

import { useState, useEffect, useCallback } from 'react'
import { useAccount, useChainId, usePublicClient } from 'wagmi'

export interface OwnedNFT {
  contractAddress: string
  tokenId:         number
  tokenURI:        string
  collectionName:  string
  tokenType:       'ERC721' | 'ERC1155'
  balance:         number
}

export interface UseNFTPortfolioReturn {
  nfts:       OwnedNFT[]
  isLoading:  boolean
  error:      string | null
  refresh:    () => void
  totalCount: number
}

// Minimal ABIs for reading NFT data
const ERC721_READ_ABI = [
  {
    name: 'balanceOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'owner', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'tokenOfOwnerByIndex', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'owner', type: 'address' }, { name: 'index', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'tokenURI', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ type: 'string' }],
  },
  {
    name: 'name', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ type: 'string' }],
  },
] as const

const ERC1155_READ_ABI = [
  {
    name: 'balanceOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }, { name: 'id', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'uri', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'id', type: 'uint256' }],
    outputs: [{ type: 'string' }],
  },
  {
    name: 'name', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ type: 'string' }],
  },
] as const

export function useNFTPortfolio(
  contractAddresses: { address: string; type: 'ERC721' | 'ERC1155'; tokenIds?: number[] }[]
): UseNFTPortfolioReturn {
  const { address }   = useAccount()
  const chainId       = useChainId()
  const publicClient  = usePublicClient()

  const [nfts,      setNfts]      = useState<OwnedNFT[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [error,     setError]     = useState<string | null>(null)

  const fetchPortfolio = useCallback(async () => {
    if (!address || !publicClient || contractAddresses.length === 0) return

    setIsLoading(true)
    setError(null)
    const result: OwnedNFT[] = []

    try {
      for (const contract of contractAddresses) {
        const addr = contract.address as `0x${string}`

        if (contract.type === 'ERC721') {
          // Get collection name
          let collectionName = 'Unknown Collection'
          try {
            collectionName = await publicClient.readContract({
              address: addr, abi: ERC721_READ_ABI, functionName: 'name',
            }) as string
          } catch {}

          // Get balance
          const balance = await publicClient.readContract({
            address: addr, abi: ERC721_READ_ABI,
            functionName: 'balanceOf', args: [address],
          }) as bigint

          if (balance === 0n) continue

          // Get each token ID owned — multicall for efficiency
          const indexCalls = Array.from({ length: Number(balance) }, (_, i) => ({
            address:      addr,
            abi:          ERC721_READ_ABI,
            functionName: 'tokenOfOwnerByIndex' as const,
            args:         [address, BigInt(i)] as [`0x${string}`, bigint],
          }))

          const tokenIds = await publicClient.multicall({
            contracts: indexCalls,
          })

          // Get tokenURIs — multicall again
          const uriCalls = tokenIds
            .filter(r => r.status === 'success')
            .map(r => ({
              address:      addr,
              abi:          ERC721_READ_ABI,
              functionName: 'tokenURI' as const,
              args:         [r.result as bigint] as [bigint],
            }))

          const uris = await publicClient.multicall({ contracts: uriCalls })

          tokenIds.forEach((tokenResult, i) => {
            if (tokenResult.status !== 'success') return
            const tokenId = Number(tokenResult.result as bigint)
            const uri     = uris[i]?.status === 'success' ? uris[i].result as string : ''

            result.push({
              contractAddress: contract.address,
              tokenId,
              tokenURI:        uri,
              collectionName,
              tokenType:       'ERC721',
              balance:         1,
            })
          })

        } else {
          // ERC-1155 — check balance for known token IDs
          const tokenIds = contract.tokenIds ?? [1, 2, 3, 4, 5]

          let collectionName = 'Unknown Collection'
          try {
            collectionName = await publicClient.readContract({
              address: addr, abi: ERC1155_READ_ABI, functionName: 'name',
            }) as string
          } catch {}

          const balanceCalls = tokenIds.map(id => ({
            address:      addr,
            abi:          ERC1155_READ_ABI,
            functionName: 'balanceOf' as const,
            args:         [address, BigInt(id)] as [`0x${string}`, bigint],
          }))

          const balances = await publicClient.multicall({ contracts: balanceCalls })

          for (let i = 0; i < tokenIds.length; i++) {
            const bal = balances[i]
            if (bal.status !== 'success' || (bal.result as bigint) === 0n) continue

            const tokenId = tokenIds[i]
            let uri = ''
            try {
              uri = await publicClient.readContract({
                address: addr, abi: ERC1155_READ_ABI,
                functionName: 'uri', args: [BigInt(tokenId)],
              }) as string
            } catch {}

            result.push({
              contractAddress: contract.address,
              tokenId,
              tokenURI:        uri,
              collectionName,
              tokenType:       'ERC1155',
              balance:         Number(bal.result as bigint),
            })
          }
        }
      }

      setNfts(result)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load NFTs')
    } finally {
      setIsLoading(false)
    }
  }, [address, publicClient, contractAddresses, chainId])

  useEffect(() => {
    fetchPortfolio()
  }, [fetchPortfolio])

  return {
    nfts,
    isLoading,
    error,
    refresh:    fetchPortfolio,
    totalCount: nfts.length,
  }
}
