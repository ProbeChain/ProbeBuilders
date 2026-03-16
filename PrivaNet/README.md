# PrivaNet — Privacy Analytics

Privacy analytics query-response marketplace on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Data Source Registration**: Providers register data sources with schema definitions
- **Privacy Queries**: Submit encrypted queries with payment budgets
- **Proof-Based Answers**: Responders submit results with privacy proofs
- **Payment Escrow**: Budget held in escrow until answer verified
- **Dispute System**: Query dispute mechanism with refund support

## Contract: PrivateQuery.sol

| Function | Description |
|---|---|
| `registerDataSource` | Register a new data source with schema |
| `submitQuery` | Submit an encrypted query with budget |
| `submitAnswer` | Provider submits encrypted answer with proof |
| `verifyAnswer` | Requester verifies and accepts answer |

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
