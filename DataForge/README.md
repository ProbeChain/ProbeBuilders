# DataForge — Synthetic Data Marketplace

Synthetic data marketplace on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Data Requests**: Post requests for synthetic data with specs, budget, and deadline
- **Submission**: Generators submit synthetic data with statistical validation hashes
- **Validation**: Authorized validators score submissions (min 70/100 to pass)
- **Payment Distribution**: Automatic split between generator, validator, and platform
- **Deadline Management**: Auto-expire and refund for unfulfilled requests

## Contract: SyntheticDataMarket.sol

| Function | Description |
|---|---|
| `requestSynthData` | Create a synthetic data generation request |
| `submitSynthData` | Submit generated synthetic data |
| `validateData` | Validator scores the submission |
| `claimPayment` | Generator claims payment for validated data |

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
