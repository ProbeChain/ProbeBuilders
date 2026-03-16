# ContentMint

Content creation and NFT minting platform with royalties and limited editions on ProbeChain Rydberg Testnet.

## Features

- Create content entries with IPFS metadata and royalty settings
- Mint limited edition NFTs from content entries
- EIP-2981 royalty support (up to 25%)
- Content versioning for updates
- Configurable edition limits per content

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: ContentNFT

| Function | Description |
|---|---|
| `createContent(contentHash, metadataURI, royaltyBPS)` | Register new content |
| `createContentWithEditions(...)` | Register with custom edition limit |
| `mintEdition(contentId, recipient)` | Mint an edition NFT |
| `updateContent(contentId, newHash, newURI)` | Update content version |
| `setRoyalty(contentId, newRoyaltyBPS)` | Update royalty percentage |
| `setMaxEditions(contentId, newMax)` | Update edition cap |
| `royaltyInfo(tokenId, salePrice)` | EIP-2981 royalty query |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
