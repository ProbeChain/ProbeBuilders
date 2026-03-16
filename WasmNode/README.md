# WasmNode — Decentralized WASM Compute

Decentralized WASM compute network on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register WASM runtimes with capabilities and stake
- Execute WASM modules with paid requests
- Submit and verify execution outputs
- Failure handling and timeout-based refunds

## Contract: WasmExecutor.sol

| Function | Description |
|---|---|
| `registerRuntime` | Register a WASM runtime with stake |
| `executeWasm` | Request WASM execution |
| `submitOutput` | Submit execution output |
| `verifyExecution` | Verify and release payment |
| `markFailed` | Mark execution as failed |

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
