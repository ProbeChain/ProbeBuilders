# AgentWallet — Budget-Controlled Agent Wallet

Smart wallet for AI agents with daily spending limits, per-transaction caps, and emergency freeze. Supports delegated operators for agent-controlled spending.

## Contracts

- **AgentWallet.sol** — Wallet creation, deposits, budget-enforced transactions, operator management, emergency controls.

## Quick Start

```bash
npm install
cp .env.example .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Key Functions

| Function | Description |
|---|---|
| `createWallet(dailyLimit, singleTxLimit)` | Create budget-controlled wallet |
| `deposit(walletId)` | Fund a wallet |
| `setSpendingLimit(walletId, limit)` | Update daily limit |
| `executeTransaction(walletId, to, value, data)` | Spend from wallet |
| `emergencyFreeze(walletId)` | Freeze all spending |
| `setOperator(walletId, operator, authorized)` | Delegate spending |

## Network

- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: `https://proscan.pro/chain/rydberg-rpc`
