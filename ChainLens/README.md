# ChainLens - On-Chain Analytics Registry

Decentralized analytics marketplace where data providers register queries and consumers pay per execution on ProbeChain Rydberg Testnet.

## Features
- Providers stake PROBE and register analytics queries
- Consumers pay to execute queries
- Providers submit result hashes on-chain
- Dispute resolution with reputation slashing
- Timeout refunds for unresponsive providers

## Deploy
```bash
npm install
cp .env.example .env  # add your private key
npx hardhat compile
npm run deploy
```

## Network
- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
