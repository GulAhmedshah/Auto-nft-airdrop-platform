// frontend/src/pages/admin/CampaignCreator.tsx
import { useState, useRef, useCallback } from 'react'
import axios from 'axios'
import { parseCSV, generateSampleCSV, ParseResult } from '../../lib/csvParser'

const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001'

// ── Styles ────────────────────────────────────────────────────────────────────
const S = {
  page:    { padding: '32px', maxWidth: '700px', margin: '0 auto', color: '#fff', fontFamily: 'sans-serif' } as const,
  title:   { fontSize: '24px', fontWeight: 700, marginBottom: '8px' } as const,
  sub:     { fontSize: '14px', color: '#888', marginBottom: '32px' } as const,
  card:    { background: '#1a1a1a', border: '1px solid #333', borderRadius: '12px', padding: '24px', marginBottom: '16px' } as const,
  section: { fontSize: '13px', fontWeight: 700, color: '#888', textTransform: 'uppercase' as const, letterSpacing: '0.05em', marginBottom: '16px' } as const,
  label:   { display: 'block', fontSize: '13px', color: '#aaa', marginBottom: '6px' } as const,
  input:   { width: '100%', background: '#0f0f0f', border: '1px solid #444', borderRadius: '8px', padding: '10px 12px', color: '#fff', fontSize: '14px', outline: 'none', boxSizing: 'border-box' as const } as const,
  select:  { width: '100%', background: '#0f0f0f', border: '1px solid #444', borderRadius: '8px', padding: '10px 12px', color: '#fff', fontSize: '14px', outline: 'none', boxSizing: 'border-box' as const } as const,
  field:   { marginBottom: '16px' } as const,
  row:     { display: 'flex', gap: '12px' } as const,
  btn:     { background: '#7C3AED', color: 'white', border: 'none', borderRadius: '8px', padding: '12px 24px', cursor: 'pointer', fontWeight: 600, fontSize: '14px' } as const,
  btnSec:  { background: 'transparent', color: '#888', border: '1px solid #444', borderRadius: '8px', padding: '12px 24px', cursor: 'pointer', fontSize: '14px' } as const,
  error:   { color: '#ef4444', fontSize: '13px', marginTop: '4px' } as const,
  hint:    { fontSize: '12px', color: '#666', marginTop: '4px' } as const,
  badge:   (type: 'Direct' | 'Merkle', selected: boolean) => ({
    flex: 1, padding: '16px', borderRadius: '10px', cursor: 'pointer',
    border: `2px solid ${selected ? '#7C3AED' : '#333'}`,
    background: selected ? '#7C3AED15' : '#0f0f0f',
    color: selected ? '#fff' : '#888',
    textAlign: 'center' as const,
  }),
}

interface FormState {
  name:             string
  contractAddress:  string
  tokenType:        'ERC721' | 'ERC1155' //string ERC721
  distributionType: 'Direct' | 'Merkle'
  tokenId:          string   // ERC-1155 only for Direct
  scheduledAt:      string   // datetime-local input value
}

const INITIAL: FormState = {
  name:             '',
  contractAddress:  '',
  tokenType:        'ERC721',
  distributionType: 'Direct',
  tokenId:          '1',
  scheduledAt:      '',
}

interface Props {
  onCreated?: (campaignId: string) => void
}

export default function CampaignCreator({ onCreated }: Props) {
  const [form,        setForm]        = useState<FormState>(INITIAL)
  const [csvText,     setCsvText]     = useState('')
  const [parseResult, setParseResult] = useState<ParseResult | null>(null)
  const [submitting,  setSubmitting]  = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  function setField<K extends keyof FormState>(k: K, v: FormState[K]) {
    setForm(f => ({ ...f, [k]: v }))
  }

  // ── CSV file upload handler ────────────────────────────────────────────────
  const handleFileUpload = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    const reader = new FileReader()
    reader.onload = (ev) => {
      const text = ev.target?.result as string
      setCsvText(text)
      const mode = form.tokenType === 'ERC1155' && form.distributionType === 'Direct'
        ? 'erc1155' : form.distributionType === 'Merkle' ? 'merkle' : 'erc721'
      setParseResult(parseCSV(text, mode))
    }
    reader.readAsText(file)
  }, [form.tokenType, form.distributionType])

  // ── Paste CSV handler ──────────────────────────────────────────────────────
  function handleCsvPaste(text: string) {
    setCsvText(text)
    const mode = form.tokenType === 'ERC1155' && form.distributionType === 'Direct'
      ? 'erc1155' : form.distributionType === 'Merkle' ? 'merkle' : 'erc721'
    setParseResult(parseCSV(text, mode))
  }

  // ── Download sample CSV ────────────────────────────────────────────────────
  function downloadSample() {
    const mode = form.tokenType === 'ERC1155' ? 'erc1155' : 'erc721'
    const content = generateSampleCSV(mode)
    const blob = new Blob([content], { type: 'text/csv' })
    const url  = URL.createObjectURL(blob)
    const a    = document.createElement('a')
    a.href = url; a.download = 'sample_recipients.csv'; a.click()
    URL.revokeObjectURL(url)
  }

  // ── Submit campaign ────────────────────────────────────────────────────────
  async function handleSubmit() {
    if (!form.name.trim())            return setSubmitError('Campaign name is required')
    if (!form.contractAddress.trim()) return setSubmitError('Contract address is required')
    if (!parseResult || parseResult.validCount === 0)
      return setSubmitError('Upload a valid CSV with at least one recipient')
    if (parseResult.errorCount > 0)
      return setSubmitError(`Fix ${parseResult.errorCount} CSV errors before submitting`)

    setSubmitting(true)
    setSubmitError(null)

    try {
      const payload = {
        name:             form.name,
        contractAddress:  form.contractAddress,
        tokenType:        form.tokenType,
        distributionType: form.distributionType,
        tokenId:          form.tokenType === 'ERC1155' ? parseInt(form.tokenId) : undefined,
        recipients:       parseResult.valid,
        scheduledAt:      form.scheduledAt
          ? new Date(form.scheduledAt).toISOString()
          : null,
      }

      const res = await axios.post(`${API_BASE}/api/campaigns`, payload, {
        withCredentials: true,
      })

      onCreated?.(res.data.id)

    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed to create campaign'
      setSubmitError(msg)
    } finally {
      setSubmitting(false)
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  return (
    <div style={S.page}>
      <div style={S.title}>Create Airdrop Campaign</div>
      <div style={S.sub}>Configure and launch a new NFT airdrop campaign.</div>

      {/* ── Section 1: Basic Info ─────────────────────────────────────── */}
      <div style={S.card}>
        <div style={S.section}>Campaign Info</div>

        <div style={S.field}>
          <label style={S.label}>Campaign Name *</label>
          <input style={S.input} value={form.name}
            onChange={e => setField('name', e.target.value)}
            placeholder="e.g. Genesis Member Airdrop" />
        </div>

        <div style={S.field}>
          <label style={S.label}>NFT Contract Address *</label>
          <input style={S.input} value={form.contractAddress}
            onChange={e => setField('contractAddress', e.target.value)}
            placeholder="0x..." />
          <div style={S.hint}>The deployed NFT721 or NFT1155 contract address.</div>
        </div>

        <div style={S.row}>
          <div style={{ ...S.field, flex: 1 }}>
            <label style={S.label}>Token Type</label>
            <select style={S.select} value={form.tokenType}
              onChange={e => setField('tokenType', e.target.value as 'ERC721' | 'ERC1155')}>
              <option value="ERC721">ERC-721 (Unique NFTs)</option>
              <option value="ERC1155">ERC-1155 (Edition NFTs)</option>
            </select>
          </div>

          {form.tokenType === 'ERC1155' && form.distributionType === 'Direct' && (
            <div style={{ ...S.field, flex: 1 }}>
              <label style={S.label}>Token ID</label>
              <input style={S.input} type="number" min="1" value={form.tokenId}
                onChange={e => setField('tokenId', e.target.value)} />
            </div>
          )}
        </div>
      </div>

      {/* ── Section 2: Distribution Type ──────────────────────────────── */}
      <div style={S.card}>
        <div style={S.section}>Distribution Method</div>
        <div style={S.row}>
          <button style={S.badge('Direct', form.distributionType === 'Direct')}
            onClick={() => setField('distributionType', 'Direct')}>
            <div style={{ fontSize: '24px', marginBottom: '6px' }}>📤</div>
            <div style={{ fontWeight: 700, marginBottom: '4px' }}>Direct Airdrop</div>
            <div style={{ fontSize: '12px', color: '#888' }}>
              Platform pushes tokens to all recipients automatically
            </div>
          </button>
          <button style={S.badge('Merkle', form.distributionType === 'Merkle')}
            onClick={() => setField('distributionType', 'Merkle')}>
            <div style={{ fontSize: '24px', marginBottom: '6px' }}>🌳</div>
            <div style={{ fontWeight: 700, marginBottom: '4px' }}>Merkle Claim</div>
            <div style={{ fontSize: '12px', color: '#888' }}>
              Recipients claim themselves using a Merkle proof
            </div>
          </button>
        </div>

        {form.distributionType === 'Merkle' && (
          <div style={{ marginTop: '12px', padding: '12px', background: '#0f0f0f',
                        borderRadius: '8px', fontSize: '13px', color: '#888' }}>
            ℹ️ A Merkle tree will be generated from your recipient list.
            The root will be stored on-chain and proofs emailed/provided to recipients.
          </div>
        )}
      </div>

      {/* ── Section 3: Recipients CSV ──────────────────────────────────── */}
      <div style={S.card}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
          <div style={S.section}>Recipients</div>
          <button style={{ ...S.btnSec, padding: '6px 12px', fontSize: '12px' }}
            onClick={downloadSample}>
            ↓ Sample CSV
          </button>
        </div>

        {/* File upload */}
        <input ref={fileRef} type="file" accept=".csv,.txt"
          style={{ display: 'none' }} onChange={handleFileUpload} />
        <button style={{ ...S.btnSec, width: '100%', marginBottom: '12px' }}
          onClick={() => fileRef.current?.click()}>
          📁 Upload CSV File
        </button>

        {/* Paste area */}
        <div style={S.field}>
          <label style={S.label}>— or paste CSV directly —</label>
          <textarea
            style={{ ...S.input, height: '120px', resize: 'vertical', fontFamily: 'monospace', fontSize: '12px' }}
            value={csvText}
            onChange={e => handleCsvPaste(e.target.value)}
            placeholder={form.tokenType === 'ERC1155'
              ? 'address,tokenId,amount\n0x1234...,1,10\n0x5678...,2,5'
              : 'address,amount\n0x1234...,2\n0x5678...,1'}
          />
        </div>

        {/* Validation summary */}
        {parseResult && (
          <ValidationSummary result={parseResult} />
        )}
      </div>

      {/* ── Section 4: Schedule ────────────────────────────────────────── */}
      <div style={S.card}>
        <div style={S.section}>Schedule (Optional)</div>
        <div style={S.field}>
          <label style={S.label}>Execute At</label>
          <input style={S.input} type="datetime-local" value={form.scheduledAt}
            onChange={e => setField('scheduledAt', e.target.value)} />
          <div style={S.hint}>Leave empty to execute immediately after creation.</div>
        </div>
      </div>

      {/* ── Submit ─────────────────────────────────────────────────────── */}
      {submitError && (
        <div style={{ ...S.error, marginBottom: '16px', padding: '12px',
                      background: '#ef444415', borderRadius: '8px' }}>
          {submitError}
        </div>
      )}

      <button style={{ ...S.btn, width: '100%', opacity: submitting ? 0.7 : 1 }}
        onClick={handleSubmit} disabled={submitting}>
        {submitting ? 'Creating Campaign...' : '🚀 Create Campaign'}
      </button>
    </div>
  )
}

// ── Validation Summary Component ──────────────────────────────────────────────
function ValidationSummary({ result }: { result: ParseResult }) {
  return (
    <div style={{ marginTop: '12px' }}>
      {/* Stats row */}
      <div style={{ display: 'flex', gap: '12px', marginBottom: '12px' }}>
        {[
          { label: 'Total Rows',    value: result.totalRows,   color: '#fff'     },
          { label: 'Valid',         value: result.validCount,  color: '#22c55e'  },
          { label: 'Errors',        value: result.errorCount,  color: '#ef4444'  },
          { label: 'Total Tokens',  value: result.totalTokens, color: '#a78bfa'  },
        ].map(({ label, value, color }) => (
          <div key={label} style={{ flex: 1, background: '#0f0f0f', borderRadius: '8px',
                                     padding: '10px', textAlign: 'center' }}>
            <div style={{ fontSize: '20px', fontWeight: 700, color }}>{value}</div>
            <div style={{ fontSize: '11px', color: '#666', marginTop: '2px' }}>{label}</div>
          </div>
        ))}
      </div>

      {/* Error list */}
      {result.errors.length > 0 && (
        <div style={{ background: '#ef444410', border: '1px solid #ef444430',
                      borderRadius: '8px', padding: '12px', maxHeight: '160px', overflow: 'auto' }}>
          <div style={{ fontSize: '12px', fontWeight: 700, color: '#ef4444', marginBottom: '8px' }}>
            ⚠️ {result.errors.length} validation error{result.errors.length > 1 ? 's' : ''}
          </div>
          {result.errors.map((e, i) => (
            <div key={i} style={{ fontSize: '12px', color: '#fca5a5', marginBottom: '4px' }}>
              Row {e.row}: {e.message}
            </div>
          ))}
        </div>
      )}

      {/* Success state */}
      {result.errorCount === 0 && result.validCount > 0 && (
        <div style={{ background: '#22c55e10', border: '1px solid #22c55e30',
                      borderRadius: '8px', padding: '10px', fontSize: '13px', color: '#22c55e' }}>
          ✓ All {result.validCount} recipients validated successfully.
          {result.totalTokens > 0 && ` ${result.totalTokens} total tokens will be distributed.`}
        </div>
      )}
    </div>
  )
}
