# NFTFactory

NFT collection factory with ERC-721 deployment, minting, and EIP-2981 royalties on ProbeChain Rydberg Testnet.

## Features

- Deploy new NFT collections with one transaction
- Configurable max supply, mint price, and royalties
- Mint via factory or directly from collection
- EIP-2981 royalty support
- Track collections per creator

## Setup

```bash
npm install
cp .env.example .env
npx hardhat compile
npm run deploy
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
