# AirProbe — Air Quality DAO

Community-governed air quality monitoring DAO on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Deploy air quality sensors by location
- Report AQI data (PM2.5, PM10, O3, CO2)
- Query sensors by area
- DAO governance with proposals and voting

## Contract: AirQualityDAO.sol

| Function | Description |
|---|---|
| `deploySensor` | Deploy an air quality sensor |
| `reportAQI` | Report air quality data |
| `getAreaQuality` | Query sensors by area |
| `proposeAction` | Create a governance proposal |
| `voteOnAction` | Vote on a proposal |

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
