# GenArtX

Generative art platform with on-chain seed generation (ERC-721) on ProbeChain Rydberg Testnet.

## Features

- **Collections** — Artists create collections with generative scripts, max supply, and mint price
- **On-Chain Seeds** — Each mint generates a unique seed from on-chain entropy (timestamp, prevrandao, minter, tokenId)
- **Secondary Sales** — List and buy art pieces with automatic royalty payments to artists
- **Configurable Royalties** — Artists set collection-level royalties (up to 10%)
- **Collection Management** — Artists can toggle collection active/inactive status

## Contract: GenerativeArt.sol (ERC-721)

| Function | Description |
|---|---|
| `createCollection(name, scriptHash, maxSupply, mintPrice)` | Create a generative art collection |
| `mint(collectionId)` | Mint a piece (generates unique seed) |
| `setCollectionRoyalty(collectionId, bps)` | Set collection royalty |
| `listForSale(tokenId, price)` | List for secondary sale |
| `buyArt(tokenId)` | Buy a listed piece |

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
