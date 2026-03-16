# TokenFactory

One-click ERC-20 token creation factory on ProbeChain Rydberg Testnet.

## Features

- Deploy new ERC-20 tokens with one transaction
- Configurable name, symbol, total supply, and decimals
- Track all deployed tokens per creator
- Optional creation fee
- Paginated token listing

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
