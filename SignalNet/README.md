# SignalNet — Wireless Coverage Protocol

Decentralized wireless coverage network on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register hotspots (WiFi, LTE, 5G, LoRa, Bluetooth)
- Report coverage metrics (users served, uptime)
- Hotspot verification by authorized verifiers
- Reward distribution from funded pool

## Contract: CoverageProtocol.sol

| Function | Description |
|---|---|
| `registerHotspot` | Register a wireless hotspot |
| `reportCoverage` | Report coverage metrics |
| `verifyHotspot` | Verify a hotspot (verifier) |
| `claimReward` | Claim pending rewards |

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
