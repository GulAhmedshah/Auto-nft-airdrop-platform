// frontend/src/components/TransactionLink.tsx
// Opens correct block explorer based on chainId

const EXPLORERS: Record<number, string> = {
  1:        'https://etherscan.io',
  137:      'https://polygonscan.com',
  42161:    'https://arbiscan.io',
  11155111: 'https://sepolia.etherscan.io',
}

interface Props {
  hash:    string
  chainId: number
  type?:   'tx' | 'address' | 'token'
  label?:  string
  short?:  boolean
}

export function TransactionLink({
  hash, chainId, type = 'tx', label, short = true
}: Props) {
  const base = EXPLORERS[chainId] ?? EXPLORERS[11155111]
  const url  = `${base}/${type}/${hash}`

  const display = label ?? (short
    ? `${hash.slice(0, 8)}...${hash.slice(-6)}`
    : hash)

  return (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      style={{
        color:          '#7C3AED',
        fontFamily:     'monospace',
        fontSize:       '13px',
        textDecoration: 'none',
      }}
      onMouseEnter={e => (e.currentTarget.style.textDecoration = 'underline')}
      onMouseLeave={e => (e.currentTarget.style.textDecoration = 'none')}
    >
      {display} ↗
    </a>
  )
}
