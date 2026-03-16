# ProbeIoT — IoT Device Registry

On-chain IoT device registry for ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register IoT devices (Sensor, Actuator, Gateway)
- Report sensor data with hash verification
- Device verification by authorized verifiers
- Device decommission lifecycle
- Paginated data query

## Contract: IoTRegistry.sol

| Function | Description |
|---|---|
| `registerDevice` | Register a new IoT device |
| `reportData` | Submit data hash from a device |
| `verifyDevice` | Verifier marks device as verified |
| `decommission` | Decommission a device |
| `getDeviceData` | Paginated data query |

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
