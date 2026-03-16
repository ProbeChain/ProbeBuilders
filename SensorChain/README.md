# SensorChain — Sensor Data Marketplace

Decentralized sensor data marketplace on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register sensors with location and data type
- Subscription-based data access with daily pricing
- On-chain sensor readings with timestamps
- Platform fee system with withdrawals

## Contract: SensorMarket.sol

| Function | Description |
|---|---|
| `registerSensor` | Register a new sensor with pricing |
| `subscribeSensor` | Subscribe to a sensor's data feed |
| `pushReading` | Push a sensor reading on-chain |
| `getReadings` | Paginated reading query |
| `withdraw` | Withdraw earnings |

## Quick Start

```bash
cp .env.example .env
# Add your private key to .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
