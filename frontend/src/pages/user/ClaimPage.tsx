// frontend/src/pages/user/ClaimPage.tsx
import { useState }                          from 'react'
import { useAccount, useChainId,
         useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import axios                                 from 'axios'
import { TransactionLink }                   from '../../components/TransactionLink'

const API_BASE = import.meta.env.VITE_API_BASE_URL    || 'http://localhost:3001'
const MERKLE_ADDRESS = import.meta.env.VITE_MERKLE_AIRDROP_ADDRESS || ''

const MERKLE_ABI = [
  {
    name: 'claim', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      { name: 'index',   type: 'uint256'    },
      { name: 'account', type: 'address'    },
      { name: 'amount',  type: 'uint256'    },
      { name: 'proof',   type: 'bytes32[]'  },
    ],
    outputs: [],
  },
  {
    name: 'isClaimed', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'index', type: 'uint256' }],
    outputs: [{ type: 'bool' }],
  },
  {
    name: 'claimOpen', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ type: 'bool' }],
  },
] as const

interface ClaimEligibility {
  eligible: boolean
  index:    number
  amount:   number
  proof:    string[]
  message?: string
}

export default function ClaimPage() {
  const { address, isConnected }  = useAccount()
  const chainId                   = useChainId()
  const { writeContractAsync }    = useWriteContract()

  const [eligibility, setEligibility] = useState<ClaimEligibility | null>(null)
  const [checking,    setChecking]    = useState(false)
  const [claiming,    setClaiming]    = useState(false)
  const [txHash,      setTxHash]      = useState<string | null>(null)
  const [error,       setError]       = useState<string | null>(null)
  const [claimed,     setClaimed]     = useState(false)

  const { isLoading: isMining, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash as `0x${string}` | undefined,
  })

  // ── Check eligibility ──────────────────────────────────────────────────────
  async function checkEligibility() {
    if (!address) return
    setChecking(true)
    setError(null)
    setEligibility(null)

    try {
      const res = await axios.get(
        `${API_BASE}/api/claims/${address}`,
        { withCredentials: true }
      )
      setEligibility(res.data)
    } catch (err: unknown) {
      if (axios.isAxiosError(err) && err.response?.status === 404) {
        setEligibility({ eligible: false, index: 0, amount: 0, proof: [],
                         message: 'Your address is not in the airdrop list.' })
      } else {
        setError('Failed to check eligibility. Please try again.')
      }
    } finally {
      setChecking(false)
    }
  }

  // ── Submit claim transaction ────────────────────────────────────────────────
  async function submitClaim() {
    if (!eligibility?.eligible || !address) return
    setClaiming(true)
    setError(null)

    try {
      const hash = await writeContractAsync({
        address:      MERKLE_ADDRESS as `0x${string}`,
        abi:          MERKLE_ABI,
        functionName: 'claim',
        args: [
          BigInt(eligibility.index),
          address as `0x${string}`,
          BigInt(eligibility.amount),
          eligibility.proof as `0x${string}`[],
        ],
      })
      setTxHash(hash)
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Transaction failed'
      setError(msg.includes('rejected') ? 'Transaction rejected by user.' : msg)
    } finally {
      setClaiming(false)
    }
  }

  if (isSuccess && !claimed) setClaimed(true)

  if (!isConnected) return (
    <div style={styles.page}>
      <div style={styles.card}>
        <p style={{ color: '#888', textAlign: 'center' }}>
          Connect your wallet to check eligibility.
        </p>
      </div>
    </div>
  )

  return (
    <div style={styles.page}>
      <h2 style={styles.title}>Claim Your Airdrop</h2>
      <p style={styles.sub}>
        Check if your wallet is eligible for a Merkle airdrop and claim your tokens.
      </p>

      <div style={styles.card}>

        {/* Wallet display */}
        <div style={styles.field}>
          <label style={styles.label}>Your Wallet</label>
          <div style={{ ...styles.input, color: '#888' }}>
            {address}
          </div>
        </div>

        {/* Check button */}
        {!eligibility && (
          <button style={styles.btnPrimary} onClick={checkEligibility}
            disabled={checking}>
            {checking ? 'Checking...' : '🔍 Check Eligibility'}
          </button>
        )}

        {/* Eligibility result */}
        {eligibility && (
          <div style={{
            background:   eligibility.eligible ? '#22c55e10' : '#ef444410',
            border:       `1px solid ${eligibility.eligible ? '#22c55e30' : '#ef444430'}`,
            borderRadius: '10px',
            padding:      '20px',
            marginTop:    '16px',
          }}>
            {eligibility.eligible ? (
              <>
                <div style={{ fontSize: '18px', fontWeight: 700, color: '#22c55e',
                              marginBottom: '12px' }}>
                  ✅ You are eligible!
                </div>
                <div style={{ fontSize: '14px', color: '#aaa', marginBottom: '8px' }}>
                  You can claim <strong style={{ color: '#fff' }}>
                    {eligibility.amount} NFT{eligibility.amount > 1 ? 's' : ''}
                  </strong>
                </div>
                <div style={{ fontSize: '12px', color: '#666' }}>
                  Merkle index: #{eligibility.index}
                </div>

                {/* Claim button */}
                {!claimed && !txHash && (
                  <button style={{ ...styles.btnPrimary, marginTop: '16px', width: '100%' }}
                    onClick={submitClaim} disabled={claiming || isMining}>
                    {claiming ? 'Waiting for signature...'
                      : isMining ? 'Mining...'
                      : '🚀 Claim Now'}
                  </button>
                )}

                {/* Tx hash */}
                {txHash && (
                  <div style={{ marginTop: '16px', padding: '12px',
                                background: '#0f0f0f', borderRadius: '8px' }}>
                    <div style={{ fontSize: '12px', color: '#888', marginBottom: '6px' }}>
                      Transaction {isMining ? '(pending...)' : '(confirmed ✅)'}
                    </div>
                    <TransactionLink hash={txHash} chainId={chainId} type="tx" />
                  </div>
                )}

                {/* Success */}
                {claimed && (
                  <div style={{ marginTop: '16px', padding: '16px', background: '#22c55e15',
                                border: '1px solid #22c55e30', borderRadius: '8px',
                                textAlign: 'center', color: '#22c55e', fontWeight: 600 }}>
                    🎉 Claimed successfully! Check your portfolio.
                  </div>
                )}
              </>
            ) : (
              <>
                <div style={{ fontSize: '16px', fontWeight: 700, color: '#ef4444',
                              marginBottom: '8px' }}>
                  ❌ Not eligible
                </div>
                <div style={{ fontSize: '13px', color: '#888' }}>
                  {eligibility.message}
                </div>
                <button style={{ ...styles.btnSecondary, marginTop: '12px' }}
                  onClick={() => setEligibility(null)}>
                  Check Different Wallet
                </button>
              </>
            )}
          </div>
        )}

        {/* Error */}
        {error && (
          <div style={{ marginTop: '12px', color: '#ef4444', fontSize: '13px' }}>
            {error}
          </div>
        )}
      </div>
    </div>
  )
}

const styles = {
  page:       { padding: '32px', maxWidth: '520px', margin: '0 auto',
                color: '#fff', fontFamily: 'sans-serif' },
  title:      { fontSize: '24px', fontWeight: 700, margin: '0 0 8px' },
  sub:        { fontSize: '14px', color: '#888', marginBottom: '24px' },
  card:       { background: '#1a1a1a', border: '1px solid #333',
                borderRadius: '12px', padding: '24px' },
  field:      { marginBottom: '16px' },
  label:      { display: 'block', fontSize: '13px', color: '#aaa', marginBottom: '6px' },
  input:      { background: '#0f0f0f', border: '1px solid #444', borderRadius: '8px',
                padding: '10px 12px', fontSize: '13px', fontFamily: 'monospace',
                wordBreak: 'break-all' as const },
  btnPrimary: { background: '#7C3AED', color: 'white', border: 'none',
                borderRadius: '8px', padding: '12px 24px', cursor: 'pointer',
                fontWeight: 600, fontSize: '14px', width: '100%' },
  btnSecondary:{ background: 'transparent', color: '#888', border: '1px solid #444',
                borderRadius: '8px', padding: '8px 16px', cursor: 'pointer',
                fontSize: '13px' },
} as const
