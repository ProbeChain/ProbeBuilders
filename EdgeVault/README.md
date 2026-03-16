# EdgeVault — Decentralized Edge Storage

Decentralized edge storage network on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register storage nodes with capacity and pricing
- Store data with duration-based payments
- Extend storage duration
- Delete data and reclaim node capacity

## Contract: EdgeStorage.sol

| Function | Description |
|---|---|
| `registerNode` | Register a storage node |
| `storeData` | Store data on a node |
| `retrieveData` | Log data retrieval |
| `extendStorage` | Extend storage duration |
| `deleteData` | Delete stored data |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
