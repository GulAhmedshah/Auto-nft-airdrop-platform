// frontend/src/hooks/useNFTPortfolio.ts
import { useState, useEffect, useCallback } from 'react'
import { useAccount, usePublicClient }      from 'wagmi'

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

const BALANCE_ABI = [{
  name: 'balanceOf', type: 'function', stateMutability: 'view',
  inputs: [{ name: 'owner', type: 'address' }],
  outputs: [{ type: 'uint256' }],
}] as const

const OWNER_ABI = [{
  name: 'ownerOf', type: 'function', stateMutability: 'view',
  inputs: [{ name: 'tokenId', type: 'uint256' }],
  outputs: [{ type: 'address' }],
}] as const

const URI_ABI = [{
  name: 'tokenURI', type: 'function', stateMutability: 'view',
  inputs: [{ name: 'tokenId', type: 'uint256' }],
  outputs: [{ type: 'string' }],
}] as const

const SUPPLY_ABI = [{
  name: 'totalSupply', type: 'function', stateMutability: 'view',
  inputs: [], outputs: [{ type: 'uint256' }],
}] as const

const NAME_ABI = [{
  name: 'name', type: 'function', stateMutability: 'view',
  inputs: [], outputs: [{ type: 'string' }],
}] as const

export function useNFTPortfolio(
  contractAddresses: { address: string; type: 'ERC721' | 'ERC1155'; tokenIds?: number[] }[]
): UseNFTPortfolioReturn {
  const { address }  = useAccount()
  const publicClient = usePublicClient()

  const [nfts,      setNfts]      = useState<OwnedNFT[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [error,     setError]     = useState<string | null>(null)

  const fetchPortfolio = useCallback(async () => {
    if (!address || !publicClient || contractAddresses.length === 0) return

    setIsLoading(true)
    setError(null)
    const result: OwnedNFT[] = []

    for (const contract of contractAddresses) {
      const addr = contract.address as `0x${string}`

      try {
        if (contract.type === 'ERC721') {

          const balance = await publicClient.readContract({
            address: addr, abi: BALANCE_ABI,
            functionName: 'balanceOf', args: [address as `0x${string}`],
          }) as bigint

          console.log('ERC721 balance:', balance.toString())
          if (balance === 0n) continue

          const supply = await publicClient.readContract({
            address: addr, abi: SUPPLY_ABI, functionName: 'totalSupply',
          }) as bigint

          console.log('Total supply:', supply.toString())

          let name = 'NFT Collection'
          try {
            name = await publicClient.readContract({
              address: addr, abi: NAME_ABI, functionName: 'name',
            }) as string
          } catch {}

          const total = Math.min(Number(supply), 200)
          let found   = 0

          for (let i = 1; i <= total && found < Number(balance); i++) {
            try {
              const owner = await publicClient.readContract({
                address: addr, abi: OWNER_ABI,
                functionName: 'ownerOf', args: [BigInt(i)],
              }) as string

              if (owner.toLowerCase() === address.toLowerCase()) {
                found++
                let uri = ''
                try {
                  uri = await publicClient.readContract({
                    address: addr, abi: URI_ABI,
                    functionName: 'tokenURI', args: [BigInt(i)],
                  }) as string
                } catch {}

                result.push({
                  contractAddress: contract.address,
                  tokenId:         i,
                  tokenURI:        uri,
                  collectionName:  name,
                  tokenType:       'ERC721',
                  balance:         1,
                })
                console.log('Found NFT:', i)
              }
            } catch {}
          }

        } else {
          const tokenIds = contract.tokenIds ?? [1,2,3,4,5]
          let name = 'Edition Collection'
          try {
            name = await publicClient.readContract({
              address: addr, abi: NAME_ABI, functionName: 'name',
            }) as string
          } catch {}

          for (const id of tokenIds) {
            try {
              const bal = await publicClient.readContract({
                address: addr,
                abi: [{ name: 'balanceOf', type: 'function', stateMutability: 'view',
                  inputs: [{ name: 'account', type: 'address' }, { name: 'id', type: 'uint256' }],
                  outputs: [{ type: 'uint256' }] }] as const,
                functionName: 'balanceOf',
                args: [address as `0x${string}`, BigInt(id)],
              }) as bigint

              if (bal === 0n) continue

              let uri = ''
              try {
                uri = await publicClient.readContract({
                  address: addr,
                  abi: [{ name: 'uri', type: 'function', stateMutability: 'view',
                    inputs: [{ name: 'id', type: 'uint256' }],
                    outputs: [{ type: 'string' }] }] as const,
                  functionName: 'uri', args: [BigInt(id)],
                }) as string
              } catch {}

              result.push({
                contractAddress: contract.address,
                tokenId:         id,
                tokenURI:        uri,
                collectionName:  name,
                tokenType:       'ERC1155',
                balance:         Number(bal),
              })
            } catch {}
          }
        }
      } catch (err) {
        console.error('Contract error:', addr, err)
        setError(`Failed to read contract ${addr.slice(0,8)}...`)
      }
    }

    console.log('Total NFTs found:', result.length)
    setNfts(result)
    setIsLoading(false)
  }, [address, publicClient, JSON.stringify(contractAddresses)])

  useEffect(() => {
    fetchPortfolio()
  }, [fetchPortfolio])

  return { nfts, isLoading, error, refresh: fetchPortfolio, totalCount: nfts.length }
}
