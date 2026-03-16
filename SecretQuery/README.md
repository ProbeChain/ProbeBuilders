# SecretQuery — Encrypted Query Engine

Encrypted query engine on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Database Registration**: Register databases with schema and public encryption key
- **Encrypted Queries**: Submit queries encrypted with the database's public key
- **Encrypted Results**: Database owners respond with encrypted results
- **Payment Escrow**: Payment held until result confirmed or auto-confirmed after timeout
- **Timeout Protection**: Refund for unanswered queries, auto-confirm for unconfirmed results

## Contract: EncryptedQueryEngine.sol

| Function | Description |
|---|---|
| `registerDatabase` | Register a database with schema and public key |
| `submitEncryptedQuery` | Submit an encrypted query with payment |
| `submitEncryptedResult` | Database owner submits encrypted result |
| `confirmResult` | Requester confirms result, releasing payment |

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
- **EVM**: London
