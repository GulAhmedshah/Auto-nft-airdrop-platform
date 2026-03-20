// frontend/src/pages/admin/DeployWizard.tsx
// ─────────────────────────────────────────────────────────────────────────────
// 4-step NFT Collection Deployment Wizard
//
// Step 1 — Token Type:     Choose ERC-721 or ERC-1155
// Step 2 — Collection:     Name, symbol, max supply
// Step 3 — Metadata:       Base URI or upload to IPFS
// Step 4 — Confirm:        Review + deploy + track status
// ─────────────────────────────────────────────────────────────────────────────

import { useState, useRef }            from 'react'
import { useAccount, useChainId }      from 'wagmi'
import { useDeployNFT, TokenType,
         DeployStatus }                from '../../hooks/useDeployNFT'

// ── Styles (inline for zero external CSS dependencies) ────────────────────────
const S = {
  page:        { padding: '32px', maxWidth: '640px', margin: '0 auto', color: '#fff', fontFamily: 'sans-serif' } as const,
  title:       { fontSize: '24px', fontWeight: 700, marginBottom: '8px' } as const,
  subtitle:    { fontSize: '14px', color: '#888', marginBottom: '32px' } as const,
  steps:       { display: 'flex', gap: '8px', marginBottom: '32px' } as const,
  step:        (active: boolean, done: boolean) => ({
    flex: 1, padding: '8px', borderRadius: '8px', textAlign: 'center' as const,
    fontSize: '12px', fontWeight: 600,
    background: done ? '#22c55e20' : active ? '#7C3AED20' : '#1a1a1a',
    border: `1px solid ${done ? '#22c55e' : active ? '#7C3AED' : '#333'}`,
    color: done ? '#22c55e' : active ? '#7C3AED' : '#666',
  }),
  card:        { background: '#1a1a1a', border: '1px solid #333', borderRadius: '12px', padding: '24px' } as const,
  label:       { display: 'block', fontSize: '13px', color: '#aaa', marginBottom: '6px' } as const,
  input:       { width: '100%', background: '#0f0f0f', border: '1px solid #444', borderRadius: '8px',
                 padding: '10px 12px', color: '#fff', fontSize: '14px', outline: 'none', boxSizing: 'border-box' as const } as const,
  fieldGroup:  { marginBottom: '16px' } as const,
  row:         { display: 'flex', gap: '12px' } as const,
  typeBtn:     (selected: boolean) => ({
    flex: 1, padding: '20px', borderRadius: '12px', cursor: 'pointer',
    border: `2px solid ${selected ? '#7C3AED' : '#333'}`,
    background: selected ? '#7C3AED20' : '#0f0f0f',
    color: selected ? '#fff' : '#888',
    textAlign: 'center' as const,
  }),
  btnPrimary:  { background: '#7C3AED', color: 'white', border: 'none', borderRadius: '8px',
                 padding: '12px 24px', cursor: 'pointer', fontWeight: 600, fontSize: '14px' } as const,
  btnSecondary:{ background: 'transparent', color: '#888', border: '1px solid #444', borderRadius: '8px',
                 padding: '12px 24px', cursor: 'pointer', fontSize: '14px' } as const,
  navRow:      { display: 'flex', justifyContent: 'space-between', marginTop: '24px' } as const,
  error:       { color: '#ef4444', fontSize: '13px', marginTop: '8px' } as const,
  hint:        { fontSize: '12px', color: '#666', marginTop: '4px' } as const,
}

// ── Form state ────────────────────────────────────────────────────────────────
interface FormData {
  tokenType:  TokenType
  name:       string
  symbol:     string
  maxSupply:  string   // string for input, converted to number on submit
  baseURI:    string
  imageFile:  File | null
}

const INITIAL_FORM: FormData = {
  tokenType: 'ERC721',
  name:      '',
  symbol:    '',
  maxSupply: '0',
  baseURI:   '',
  imageFile: null,
}

// ── Step labels ───────────────────────────────────────────────────────────────
const STEPS = ['Token Type', 'Collection', 'Metadata', 'Deploy']

// ── Explorer URL helper ───────────────────────────────────────────────────────
function explorerUrl(chainId: number, hash: string, type: 'tx' | 'address' = 'tx'): string {
  const bases: Record<number, string> = {
    1:        'https://etherscan.io',
    137:      'https://polygonscan.com',
    42161:    'https://arbiscan.io',
    11155111: 'https://sepolia.etherscan.io',
  }
  const base = bases[chainId] ?? 'https://sepolia.etherscan.io'
  return `${base}/${type}/${hash}`
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Component
// ─────────────────────────────────────────────────────────────────────────────

export default function DeployWizard() {
  const { isConnected }    = useAccount()
  const chainId            = useChainId()
  const fileInputRef       = useRef<HTMLInputElement>(null)

  const [step,       setStep]       = useState(0)
  const [form,       setForm]       = useState<FormData>(INITIAL_FORM)
  const [formErrors, setFormErrors] = useState<Partial<Record<keyof FormData, string>>>({})

  const {
    status, txHash, contractAddress, error,
    deployNFT721, deployNFT1155, uploadToIPFS, reset,
  } = useDeployNFT()

  // ── Field updater ──────────────────────────────────────────────────────────
  function setField<K extends keyof FormData>(key: K, value: FormData[K]) {
    setForm(f => ({ ...f, [key]: value }))
    setFormErrors(e => ({ ...e, [key]: undefined }))
  }

  // ── Validation per step ───────────────────────────────────────────────────
  function validateStep(s: number): boolean {
    const errors: Partial<Record<keyof FormData, string>> = {}

    if (s === 1) {
      if (!form.name.trim())   errors.name   = 'Collection name is required'
      if (!form.symbol.trim()) errors.symbol = 'Symbol is required'
      if (form.symbol.length > 10) errors.symbol = 'Symbol must be 10 characters or less'
      if (form.tokenType === 'ERC721') {
        const ms = parseInt(form.maxSupply)
        if (isNaN(ms) || ms < 0) errors.maxSupply = 'Must be 0 (unlimited) or a positive number'
      }
    }

    if (s === 2) {
      if (!form.baseURI.trim() && !form.imageFile) {
        errors.baseURI = 'Enter a base URI or upload an image'
      }
      if (form.baseURI && !form.baseURI.startsWith('ipfs://') && !form.baseURI.startsWith('https://')) {
        errors.baseURI = 'Base URI must start with ipfs:// or https://'
      }
    }

    setFormErrors(errors)
    return Object.keys(errors).length === 0
  }

  // ── Next / Back ────────────────────────────────────────────────────────────
  function next() {
    if (validateStep(step)) setStep(s => s + 1)
  }

  function back() {
    setStep(s => s - 1)
    setFormErrors({})
  }

  // ── Deploy handler ─────────────────────────────────────────────────────────
  async function handleDeploy() {
    let baseURI = form.baseURI

    // If file uploaded, send to IPFS first
    if (form.imageFile && !baseURI) {
      try {
        baseURI = await uploadToIPFS(form.imageFile, form.name)
        setField('baseURI', baseURI)
      } catch {
        setFormErrors({ baseURI: 'IPFS upload failed. Enter a base URI manually.' })
        return
      }
    }

    if (form.tokenType === 'ERC721') {
      await deployNFT721({
        name:      form.name,
        symbol:    form.symbol,
        baseURI,
        maxSupply: parseInt(form.maxSupply) || 0,
      })
    } else {
      await deployNFT1155({
        name:    form.name,
        symbol:  form.symbol,
        baseURI,
      })
    }
  }

  // ── Reset and start over ──────────────────────────────────────────────────
  function handleReset() {
    reset()
    setStep(0)
    setForm(INITIAL_FORM)
    setFormErrors({})
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  if (!isConnected) {
    return (
      <div style={S.page}>
        <div style={S.card}>
          <p style={{ color: '#888', textAlign: 'center' }}>
            Connect your wallet to deploy NFT collections.
          </p>
        </div>
      </div>
    )
  }

  return (
    <div style={S.page}>
      <div style={S.title}>Deploy NFT Collection</div>
      <div style={S.subtitle}>
        Deploy a new ERC-721 or ERC-1155 contract directly from your wallet.
      </div>

      {/* Step indicators */}
      <div style={S.steps}>
        {STEPS.map((label, i) => (
          <div key={i} style={S.step(i === step, i < step)}>
            {i < step ? '✓ ' : `${i + 1}. `}{label}
          </div>
        ))}
      </div>

      <div style={S.card}>

        {/* ── Step 0: Token Type ─────────────────────────────────────────── */}
        {step === 0 && (
          <>
            <p style={{ color: '#aaa', marginTop: 0, marginBottom: '20px', fontSize: '14px' }}>
              Choose the token standard for your collection.
            </p>
            <div style={S.row}>
              <button
                style={S.typeBtn(form.tokenType === 'ERC721')}
                onClick={() => setField('tokenType', 'ERC721')}
              >
                <div style={{ fontSize: '28px', marginBottom: '8px' }}>🖼️</div>
                <div style={{ fontWeight: 700, marginBottom: '4px' }}>ERC-721</div>
                <div style={{ fontSize: '12px', color: '#888' }}>
                  Unique NFTs — each token is one-of-a-kind
                </div>
              </button>
              <button
                style={S.typeBtn(form.tokenType === 'ERC1155')}
                onClick={() => setField('tokenType', 'ERC1155')}
              >
                <div style={{ fontSize: '28px', marginBottom: '8px' }}>📦</div>
                <div style={{ fontWeight: 700, marginBottom: '4px' }}>ERC-1155</div>
                <div style={{ fontSize: '12px', color: '#888' }}>
                  Edition NFTs — multiple copies per token ID
                </div>
              </button>
            </div>
            <div style={S.navRow}>
              <span />
              <button style={S.btnPrimary} onClick={next}>Next →</button>
            </div>
          </>
        )}

        {/* ── Step 1: Collection Details ────────────────────────────────── */}
        {step === 1 && (
          <>
            <div style={S.row}>
              <div style={{ ...S.fieldGroup, flex: 2 }}>
                <label style={S.label}>Collection Name *</label>
                <input
                  style={S.input}
                  value={form.name}
                  onChange={e => setField('name', e.target.value)}
                  placeholder="e.g. My Airdrop Collection"
                />
                {formErrors.name && <div style={S.error}>{formErrors.name}</div>}
              </div>
              <div style={{ ...S.fieldGroup, flex: 1 }}>
                <label style={S.label}>Symbol *</label>
                <input
                  style={S.input}
                  value={form.symbol}
                  onChange={e => setField('symbol', e.target.value.toUpperCase())}
                  placeholder="e.g. MAC"
                  maxLength={10}
                />
                {formErrors.symbol && <div style={S.error}>{formErrors.symbol}</div>}
              </div>
            </div>

            {form.tokenType === 'ERC721' && (
              <div style={S.fieldGroup}>
                <label style={S.label}>Max Supply</label>
                <input
                  style={S.input}
                  type="number"
                  min="0"
                  value={form.maxSupply}
                  onChange={e => setField('maxSupply', e.target.value)}
                  placeholder="0"
                />
                <div style={S.hint}>Enter 0 for unlimited supply.</div>
                {formErrors.maxSupply && <div style={S.error}>{formErrors.maxSupply}</div>}
              </div>
            )}

            <div style={S.navRow}>
              <button style={S.btnSecondary} onClick={back}>← Back</button>
              <button style={S.btnPrimary}   onClick={next}>Next →</button>
            </div>
          </>
        )}

        {/* ── Step 2: Metadata / Base URI ───────────────────────────────── */}
        {step === 2 && (
          <>
            <div style={S.fieldGroup}>
              <label style={S.label}>Base URI</label>
              <input
                style={S.input}
                value={form.baseURI}
                onChange={e => setField('baseURI', e.target.value)}
                placeholder="ipfs://QmYourHash.../"
              />
              <div style={S.hint}>
                Must end with /. Tokens resolve to baseURI + tokenId + .json
              </div>
              {formErrors.baseURI && <div style={S.error}>{formErrors.baseURI}</div>}
            </div>

            <div style={{ ...S.fieldGroup, marginTop: '8px' }}>
              <label style={S.label}>— or upload collection image to IPFS —</label>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                style={{ display: 'none' }}
                onChange={e => setField('imageFile', e.target.files?.[0] ?? null)}
              />
              <button
                style={{ ...S.btnSecondary, width: '100%' }}
                onClick={() => fileInputRef.current?.click()}
              >
                {form.imageFile ? `✓ ${form.imageFile.name}` : '📁 Choose Image File'}
              </button>
              <div style={S.hint}>
                Image will be pinned to IPFS via Pinata. Base URI returned automatically.
              </div>
            </div>

            <div style={S.navRow}>
              <button style={S.btnSecondary} onClick={back}>← Back</button>
              <button style={S.btnPrimary}   onClick={next}>Review →</button>
            </div>
          </>
        )}

        {/* ── Step 3: Confirm + Deploy ──────────────────────────────────── */}
        {step === 3 && (
          <>
            {/* Summary */}
            {status === 'idle' && (
              <>
                <p style={{ color: '#aaa', marginTop: 0, fontSize: '14px' }}>
                  Review your collection details before deploying.
                </p>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '14px' }}>
                 <tbody>
                  {[
                    ['Type',       form.tokenType],
                    ['Name',       form.name],
                    ['Symbol',     form.symbol],
                    ...(form.tokenType === 'ERC721'
                      ? [['Max Supply', form.maxSupply === '0' ? 'Unlimited' : form.maxSupply]]
                      : []),
                    ['Base URI',   form.baseURI || (form.imageFile ? '(upload on deploy)' : '—')],
                  ].map(([k, v]) => (
                    <tr key={k} style={{ borderBottom: '1px solid #2a2a2a' }}>
                      <td style={{ padding: '8px 0', color: '#888', width: '120px' }}>{k}</td>
                      <td style={{ padding: '8px 0', wordBreak: 'break-all' }}>{v}</td>
                    </tr>
                  ))}
                  </tbody>
                </table>

                {error && <div style={{ ...S.error, marginTop: '16px' }}>{error}</div>}

                <div style={S.navRow}>
                  <button style={S.btnSecondary} onClick={back}>← Back</button>
                  <button style={S.btnPrimary}   onClick={handleDeploy}>
                    🚀 Deploy Contract
                  </button>
                </div>
              </>
            )}

            {/* Status tracker */}
            {status !== 'idle' && (
              <DeployStatusTracker
                status={status}
                txHash={txHash}
                contractAddress={contractAddress}
                chainId={chainId}
                error={error}
                onReset={handleReset}
              />
            )}
          </>
        )}

      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// DeployStatusTracker — shows deploying → mined → done progression
// ─────────────────────────────────────────────────────────────────────────────

interface TrackerProps {
  status:          DeployStatus
  txHash:          string | null
  contractAddress: string | null
  chainId:         number
  error:           string | null
  onReset:         () => void
}

function DeployStatusTracker({
  status, txHash, contractAddress, chainId, error, onReset
}: TrackerProps) {

  const steps: { key: DeployStatus[]; label: string; icon: string }[] = [
    { key: ['uploading'],          label: 'Uploading to IPFS',    icon: '📤' },
    { key: ['deploying'],          label: 'Deploying contract',   icon: '⛓️' },
    { key: ['mined', 'saving'],    label: 'Transaction mined',    icon: '✅' },
    { key: ['saving'],             label: 'Saving to database',   icon: '💾' },
    { key: ['done'],               label: 'Complete!',            icon: '🎉' },
  ]

  const statusOrder: DeployStatus[] = ['idle','uploading','deploying','mined','saving','done']
  const currentIdx = statusOrder.indexOf(status)

  return (
    <div>
      <p style={{ color: '#aaa', marginTop: 0, fontSize: '14px', marginBottom: '20px' }}>
        {status === 'error' ? 'Deployment failed.' : 'Deploying your collection...'}
      </p>

      {steps.map(({ key, label, icon }, i) => {
        const stepIdx  = statusOrder.indexOf(key[0])
        const isDone   = currentIdx > stepIdx
        const isActive = key.includes(status)

        return (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: '12px',
            padding: '10px 0',
            borderBottom: '1px solid #222',
            opacity: stepIdx > currentIdx ? 0.3 : 1,
          }}>
            <span style={{ fontSize: '20px' }}>
              {isDone ? '✅' : isActive ? '⏳' : icon}
            </span>
            <span style={{
              fontSize: '14px',
              color: isDone ? '#22c55e' : isActive ? '#fff' : '#666',
              fontWeight: isActive ? 600 : 400,
            }}>
              {label}
              {isActive && status !== 'done' && '...'}
            </span>
          </div>
        )
      })}

      {/* Tx hash link */}
      {txHash && (
        <div style={{ marginTop: '16px', padding: '12px', background: '#0f0f0f', borderRadius: '8px' }}>
          <div style={{ fontSize: '12px', color: '#888', marginBottom: '4px' }}>Transaction</div>
          <a
            href={explorerUrl(chainId, txHash, 'tx')}
            target="_blank"
            rel="noopener noreferrer"
            style={{ color: '#7C3AED', fontSize: '13px', wordBreak: 'break-all' }}
          >
            {txHash.slice(0, 20)}...{txHash.slice(-8)} ↗
          </a>
        </div>
      )}

      {/* Contract address */}
      {contractAddress && (
        <div style={{ marginTop: '12px', padding: '12px', background: '#0f0f0f', borderRadius: '8px' }}>
          <div style={{ fontSize: '12px', color: '#888', marginBottom: '4px' }}>Contract Address</div>
          <a
            href={explorerUrl(chainId, contractAddress, 'address')}
            target="_blank"
            rel="noopener noreferrer"
            style={{ color: '#22c55e', fontSize: '13px', wordBreak: 'break-all' }}
          >
            {contractAddress} ↗
          </a>
        </div>
      )}

      {/* Error */}
      {error && (
        <div style={{ marginTop: '16px', color: '#ef4444', fontSize: '13px' }}>{error}</div>
      )}

      {/* Done / retry buttons */}
      {(status === 'done' || status === 'error') && (
        <div style={{ marginTop: '20px' }}>
          <button style={S.btnPrimary} onClick={onReset}>
            {status === 'done' ? '+ Deploy Another' : '↺ Try Again'}
          </button>
        </div>
      )}
    </div>
  )
}


