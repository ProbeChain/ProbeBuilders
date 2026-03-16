# FleetNet — Vehicle Fleet Telemetry

Vehicle fleet telemetry and management on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register vehicles (Car, Truck, Van, Bus, Motorcycle)
- Report telemetry: speed, location, fuel level
- Configurable alerts for speed and fuel thresholds
- Paginated telemetry history

## Contract: FleetManager.sol

| Function | Description |
|---|---|
| `registerVehicle` | Register a fleet vehicle |
| `reportTelemetry` | Report vehicle telemetry data |
| `setAlert` | Set alert thresholds |
| `getVehicleHistory` | Query telemetry history |

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
