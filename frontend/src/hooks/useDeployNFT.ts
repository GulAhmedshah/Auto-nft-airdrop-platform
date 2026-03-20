// frontend/src/hooks/useDeployNFT.ts
// ─────────────────────────────────────────────────────────────────────────────
// useDeployNFT — deploys NFT721 or NFT1155 contracts directly from the browser
//
// ── How contract deployment works from the browser ───────────────────────────
//
//   Unlike calling a function on an existing contract, deployment sends a
//   transaction with NO "to" address — just bytecode + constructor args.
//   The EVM creates the contract and returns its address in the receipt.
//
//   wagmi's useDeployContract hook handles this:
//     1. Encodes: bytecode + abi.encode(constructorArgs)
//     2. Sends tx via MetaMask
//     3. Waits for receipt
//     4. Returns the new contract address from receipt.contractAddress
//
// ── Bytecode requirement ──────────────────────────────────────────────────────
//   The bytecode must come from your compiled contracts.
//   Run: forge inspect NFT721 bytecode
//   Paste the output into frontend/src/abis/NFT721.ts as NFT721_BYTECODE
// ─────────────────────────────────────────────────────────────────────────────

import { useState, useCallback }          from 'react'
import { useDeployContract, usePublicClient,
         useAccount }                     from 'wagmi'
import { decodeEventLog }                 from 'viem'
import axios                              from 'axios'
//import { NFT721_ABI,  NFT721_BYTECODE }   from '../abis/NFT721'
//import { NFT1155_ABI, NFT1155_BYTECODE }  from '../abis/NFT1155'

import { NFT721_ABI,  NFT721_BYTECODE,
         NFT1155_ABI, NFT1155_BYTECODE }  from '../abis'



const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001'

// ── Types ─────────────────────────────────────────────────────────────────────

export type TokenType = 'ERC721' | 'ERC1155'

export type DeployStatus =
  | 'idle'
  | 'uploading'   // uploading metadata to IPFS
  | 'deploying'   // tx sent, waiting for confirmation
  | 'mined'       // tx confirmed, contract address known
  | 'saving'      // saving to backend DB
  | 'done'        // all complete
  | 'error'

export interface DeployNFT721Params {
  name:       string
  symbol:     string
  baseURI:    string
  maxSupply:  number   // 0 = unlimited
}

export interface DeployNFT1155Params {
  name:    string
  symbol:  string
  baseURI: string
}

export interface DeployResult {
  contractAddress: string
  txHash:          string
  tokenType:       TokenType
  chainId:         number
}

export interface UseDeployNFTReturn {
  status:          DeployStatus
  txHash:          string | null
  contractAddress: string | null
  error:           string | null
  deployNFT721:    (params: DeployNFT721Params)  => Promise<void>
  deployNFT1155:   (params: DeployNFT1155Params) => Promise<void>
  uploadToIPFS:    (file: File, name: string)     => Promise<string>
  reset:           () => void
}

// ── Hook ──────────────────────────────────────────────────────────────────────

export function useDeployNFT(): UseDeployNFTReturn {
  const { address }               = useAccount()
  const { deployContractAsync }   = useDeployContract()
  const publicClient              = usePublicClient()

  const [status,          setStatus]          = useState<DeployStatus>('idle')
  const [txHash,          setTxHash]          = useState<string | null>(null)
  const [contractAddress, setContractAddress] = useState<string | null>(null)
  const [error,           setError]           = useState<string | null>(null)

  // ── Reset state ─────────────────────────────────────────────────────────────
  const reset = useCallback(() => {
    setStatus('idle')
    setTxHash(null)
    setContractAddress(null)
    setError(null)
  }, [])

  // ── Upload metadata to IPFS via backend ──────────────────────────────────────
  const uploadToIPFS = useCallback(async (
    file: File,
    collectionName: string
  ): Promise<string> => {
    setStatus('uploading')

    const formData = new FormData()
    formData.append('file', file)
    formData.append('name', collectionName)

    const res = await axios.post(
      `${API_BASE}/api/ipfs/upload`,
      formData,
      {
        withCredentials: true,
        headers: { 'Content-Type': 'multipart/form-data' },
      }
    )

    return res.data.baseURI // e.g. "ipfs://QmXxx.../"
  }, [])

  // ── Save deployed collection to backend DB ────────────────────────────────
  const saveToBackend = useCallback(async (result: DeployResult) => {
    setStatus('saving')
    try {
      await axios.post(
        `${API_BASE}/api/collections`,
        result,
        { withCredentials: true }
      )
    } catch {
      // Non-fatal — contract is deployed on-chain even if DB save fails
      console.warn('Failed to save collection to backend — contract is live on-chain')
    }
  }, [])

  // ── Deploy NFT721 ────────────────────────────────────────────────────────────
  const deployNFT721 = useCallback(async (params: DeployNFT721Params) => {
    if (!address) { setError('Wallet not connected'); return }
    if (!publicClient) { setError('No public client'); return }

    setStatus('deploying')
    setError(null)

    try {
      // Send deployment transaction — MetaMask will prompt for confirmation
      const hash = await deployContractAsync({
        abi:              NFT721_ABI,
        bytecode:         NFT721_BYTECODE as `0x${string}`,
        args: [
          params.name,
          params.symbol,
          params.baseURI,
          BigInt(params.maxSupply),
          address,  // admin = deployer wallet
        ],
      })

      setTxHash(hash)
      setStatus('deploying')

      // Wait for transaction to be mined (1 confirmation)
      const receipt = await publicClient.waitForTransactionReceipt({
        hash,
        confirmations: 1,
      })

      const deployed = receipt.contractAddress
      if (!deployed) throw new Error('No contract address in receipt')

      setContractAddress(deployed)
      setStatus('mined')

      // Save to backend
      await saveToBackend({
        contractAddress: deployed,
        txHash:          hash,
        tokenType:       'ERC721',
        chainId:         await publicClient.getChainId(),
      })

      setStatus('done')

    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Deployment failed'
      setError(msg.includes('rejected') ? 'Transaction rejected by user.' : msg)
      setStatus('error')
    }
  }, [address, publicClient, deployContractAsync, saveToBackend])

  // ── Deploy NFT1155 ───────────────────────────────────────────────────────────
  const deployNFT1155 = useCallback(async (params: DeployNFT1155Params) => {
    if (!address) { setError('Wallet not connected'); return }
    if (!publicClient) { setError('No public client'); return }

    setStatus('deploying')
    setError(null)

    try {
      const hash = await deployContractAsync({
        abi:      NFT1155_ABI,
        bytecode: NFT1155_BYTECODE as `0x${string}`,
        args: [
          params.name,
          params.symbol,
          params.baseURI,
          address,
        ],
      })

      setTxHash(hash)

      const receipt = await publicClient.waitForTransactionReceipt({
        hash,
        confirmations: 1,
      })

      const deployed = receipt.contractAddress
      if (!deployed) throw new Error('No contract address in receipt')

      setContractAddress(deployed)
      setStatus('mined')

      await saveToBackend({
        contractAddress: deployed,
        txHash:          hash,
        tokenType:       'ERC1155',
        chainId:         await publicClient.getChainId(),
      })

      setStatus('done')

    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Deployment failed'
      setError(msg.includes('rejected') ? 'Transaction rejected by user.' : msg)
      setStatus('error')
    }
  }, [address, publicClient, deployContractAsync, saveToBackend])

  return {
    status,
    txHash,
    contractAddress,
    error,
    deployNFT721,
    deployNFT1155,
    uploadToIPFS,
    reset,
  }
}
