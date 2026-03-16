# ProbeGold

Gold-backed ERC-20 token with reserve proof tracking on ProbeChain Rydberg Testnet.

## Features

- ERC-20 compliant gold-backed token (pGOLD)
- Mint with reserve proof hashes
- Track gold reserve backing ratio
- Reserve proof history
- Authorized minter management

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
