import NFT721_ABI_JSON  from './NFT721.json'
import NFT1155_ABI_JSON from './NFT1155.json'
import NFT721_BYTECODE_RAW  from './NFT721_bytecode.txt?raw'
import NFT1155_BYTECODE_RAW from './NFT1155_bytecode.txt?raw'

export const NFT721_ABI      = NFT721_ABI_JSON
export const NFT721_BYTECODE = NFT721_BYTECODE_RAW.trim() as `0x${string}`

export const NFT1155_ABI      = NFT1155_ABI_JSON
export const NFT1155_BYTECODE = NFT1155_BYTECODE_RAW.trim() as `0x${string}`