# PixelMint

AI image minting with full provenance tracking (ERC-721) on ProbeChain Rydberg Testnet.

## Features

- **AI Image Minting** — Mint NFTs with prompt hash, image hash, and model provenance
- **Provenance Chain** — On-chain record: prompt -> model -> image
- **Marketplace** — List and buy image NFTs with automatic payments
- **Royalties** — Creator-defined royalty (up to 10%) on secondary sales
- **Duplicate Prevention** — Image hash uniqueness enforcement

## Contract: ImageMintFactory.sol (ERC-721)

| Function | Description |
|---|---|
| `mintImage(promptHash, imageHash, modelUsed)` | Mint an AI image NFT |
| `listForSale(tokenId, price)` | List NFT for sale |
| `buyImage(tokenId)` | Buy a listed NFT |
| `setRoyalty(tokenId, bps)` | Set royalty percentage |

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
- **EVM**: London
