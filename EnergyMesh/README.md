# EnergyMesh — Peer-to-Peer Energy Trading

Peer-to-peer energy trading marketplace on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register as energy producer (Solar, Wind, Hydro, Biomass, Geothermal)
- List energy for sale with per-kWh pricing
- Purchase energy with automatic settlement
- Generation and consumption tracking

## Contract: EnergyMarket.sol

| Function | Description |
|---|---|
| `registerProducer` | Register as an energy producer |
| `listEnergy` | List energy for sale |
| `purchaseEnergy` | Buy energy from a listing |
| `reportGeneration` | Report energy generation |
| `reportConsumption` | Report energy consumption |

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
