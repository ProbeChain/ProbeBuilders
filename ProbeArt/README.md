# ProbeArt - AI Art Gallery with Curation

Decentralized art gallery with curator consensus for featuring artworks on ProbeChain Rydberg Testnet.

## Features

- **Art Submission**: Artists submit artwork with content hash and metadata URI
- **Curator System**: Approved curators score artworks 0-100
- **Consensus Featuring**: Artworks auto-featured when enough curators give high scores
- **Direct Purchase**: Buy artworks at artist-set prices with platform fee
- **Curator Management**: Owner adds/removes curators

## Contract: ArtGallery.sol

| Function | Description |
|----------|-------------|
| `submitArtwork(artHash, metadataURI, price)` | Submit artwork |
| `curateArtwork(artworkId, score)` | Score as curator |
| `purchaseArtwork(artworkId)` | Buy artwork |
| `addCurator(address)` | Add curator (owner) |
| `removeCurator(address)` | Remove curator (owner) |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
