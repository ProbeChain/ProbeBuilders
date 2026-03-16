# ThreeDForge

3D model marketplace with ERC-721 NFTs and usage licensing on ProbeChain Rydberg Testnet.

## Features

- **3D Model Minting** — Mint NFTs for 3D models with format type (glTF, FBX, OBJ) and polygon count metadata
- **Marketplace** — List and purchase 3D model NFTs
- **Usage Licensing** — Grant usage licenses with terms (Personal, Commercial, Extended, Exclusive)
- **Duplicate Prevention** — Model hash uniqueness enforcement
- **Platform Fees** — Configurable platform fee on sales

## Contract: ThreeDMarket.sol (ERC-721)

| Function | Description |
|---|---|
| `mint3DModel(modelHash, formatType, polyCount, metadataURI)` | Mint a 3D model NFT |
| `listModel(tokenId, price)` | List for sale |
| `purchaseModel(tokenId)` | Purchase a listed model |
| `licenseForUse(tokenId, licensee, terms)` | Grant a usage license |

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
