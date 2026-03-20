// frontend/src/lib/csvParser.ts
// ─────────────────────────────────────────────────────────────────────────────
// CSV parser for airdrop recipient lists.
//
// Expected CSV formats:
//
//   ERC-721 Direct:
//     address, quantity
//     0x1234..., 2
//     0x5678..., 1
//
//   ERC-1155 Direct:
//     address, tokenId, amount
//     0x1234..., 1, 10
//     0x5678..., 2, 5
//
//   Merkle (both types):
//     address, amount
//     0x1234..., 2
//     0x5678..., 3
// ─────────────────────────────────────────────────────────────────────────────

export interface RecipientRow {
  index:    number
  address:  string
  amount:   number
  tokenId?: number   // ERC-1155 only
}

export interface ParseResult {
  valid:       RecipientRow[]
  errors:      { row: number; message: string }[]
  totalRows:   number
  validCount:  number
  errorCount:  number
  totalTokens: number
}

// ── Ethereum address validator ────────────────────────────────────────────────
function isValidAddress(addr: string): boolean {
  return /^0x[0-9a-fA-F]{40}$/.test(addr.trim())
}

// ── Main parse function ───────────────────────────────────────────────────────
export function parseCSV(
  csvText: string,
  mode: 'erc721' | 'erc1155' | 'merkle'
): ParseResult {
  const lines  = csvText.trim().split('\n')
  const valid: RecipientRow[]                    = []
  const errors: { row: number; message: string }[] = []

  // Skip header row if present
  const startLine = lines[0].toLowerCase().includes('address') ? 1 : 0

  lines.slice(startLine).forEach((line, idx) => {
    const rowNum = idx + startLine + 1
    const cols   = line.split(',').map(c => c.trim().replace(/"/g, ''))

    if (cols.length === 0 || cols[0] === '') return // skip empty lines

    const address = cols[0]

    // Validate address
    if (!isValidAddress(address)) {
      errors.push({ row: rowNum, message: `Invalid Ethereum address: "${address}"` })
      return
    }

    // ERC-1155: address, tokenId, amount
    if (mode === 'erc1155') {
      if (cols.length < 3) {
        errors.push({ row: rowNum, message: 'ERC-1155 rows need: address, tokenId, amount' })
        return
      }
      const tokenId = parseInt(cols[1])
      const amount  = parseInt(cols[2])

      if (isNaN(tokenId) || tokenId < 0) {
        errors.push({ row: rowNum, message: `Invalid tokenId: "${cols[1]}"` })
        return
      }
      if (isNaN(amount) || amount <= 0) {
        errors.push({ row: rowNum, message: `Invalid amount: "${cols[2]}"` })
        return
      }

      valid.push({ index: valid.length, address, amount, tokenId })
      return
    }

    // ERC-721 / Merkle: address, amount
    if (cols.length < 2) {
      errors.push({ row: rowNum, message: 'Row needs: address, amount' })
      return
    }

    const amount = parseInt(cols[1])
    if (isNaN(amount) || amount <= 0) {
      errors.push({ row: rowNum, message: `Invalid amount: "${cols[1]}"` })
      return
    }

    valid.push({ index: valid.length, address, amount })
  })

  const totalTokens = valid.reduce((sum, r) => sum + r.amount, 0)

  return {
    valid,
    errors,
    totalRows:   valid.length + errors.length,
    validCount:  valid.length,
    errorCount:  errors.length,
    totalTokens,
  }
}

// ── Generate sample CSV for download ─────────────────────────────────────────
export function generateSampleCSV(mode: 'erc721' | 'erc1155' | 'merkle'): string {
  if (mode === 'erc1155') {
    return [
      'address,tokenId,amount',
      '0x70997970C51812dc3A010C7d01b50e0d17dc79C8,1,10',
      '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,1,5',
      '0x90F79bf6EB2c4f870365E785982E1f101E93b906,2,3',
    ].join('\n')
  }
  return [
    'address,amount',
    '0x70997970C51812dc3A010C7d01b50e0d17dc79C8,2',
    '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,1',
    '0x90F79bf6EB2c4f870365E785982E1f101E93b906,3',
  ].join('\n')
}
