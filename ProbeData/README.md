# ProbeData — Data Marketplace

Decentralized data marketplace on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Dataset Listing**: Providers stake tokens and list datasets with pricing and licensing
- **Purchase & Access**: Buyers pay for dataset access with encrypted download keys
- **Quality Scoring**: 1-5 star rating system for purchased datasets
- **Provider Staking**: Minimum stake requirement ensures provider accountability
- **Platform Fees**: 2.5% fee on purchases for platform sustainability

## Contract: DataMarketplace.sol

| Function | Description |
|---|---|
| `listDataset` | List a new dataset with name, description, sample hash, price, and license |
| `purchaseDataset` | Purchase access to a dataset |
| `rateDataset` | Rate a purchased dataset (1-5 stars) |
| `downloadKey` | Retrieve encrypted download key for purchased dataset |
| `stakeAsProvider` | Stake tokens to become a data provider |

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
