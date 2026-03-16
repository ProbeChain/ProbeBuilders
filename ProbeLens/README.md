# ProbeLens — Analytics Dashboard Registry

Analytics dashboard registry on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Dashboard Creation**: Create dashboards composed of query hashes
- **Publishing**: Publish dashboards with subscription pricing
- **Subscriptions**: Time-limited subscriptions (30 days) with auto-expiry
- **Rating System**: 1-5 star ratings from subscribers
- **Creator Monetization**: Automatic earnings tracking and withdrawal

## Contract: DashboardRegistry.sol

| Function | Description |
|---|---|
| `createDashboard` | Create a new dashboard with query hashes |
| `publishDashboard` | Publish a draft dashboard with price |
| `subscribeToDashboard` | Subscribe to a published dashboard |
| `rateDashboard` | Rate a subscribed dashboard (1-5) |

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
