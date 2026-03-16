# WhaleWatch - Whale Wallet Tracker Registry

On-chain registry for tracking whale wallets and large transaction movements on ProbeChain Rydberg Testnet.

## Features

- **Whale Registration**: Register whale wallets with human-readable labels
- **Transaction Recording**: Log transactions with type (Transfer, Swap, Stake, etc.), amount, and reference hash
- **Whale Alerts**: Automatic alert events emitted when transactions exceed threshold
- **Batch Recording**: Record up to 50 transactions in a single call
- **Activity Analytics**: Total tx count, volume, largest tx, and last active timestamp per whale

## Contract: WhaleTracker.sol

| Function | Description |
|----------|-------------|
| `registerWhale(wallet, label)` | Register a whale wallet |
| `recordTransaction(wallet, type, amount, ts, hash)` | Record a transaction |
| `batchRecordTransactions(...)` | Batch record up to 50 txs |
| `getWhaleActivity(wallet)` | Get whale activity summary |
| `setThreshold(minAmount)` | Set alert threshold |

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
