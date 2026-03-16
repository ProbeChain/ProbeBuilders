# HashForge — Optimistic Compute Verification

Optimistic compute verification protocol on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Submit compute jobs with stake
- Optimistic verification with challenge period
- Challenge incorrect results with counter-proofs
- Arbiter-based dispute resolution with slashing

## Contract: ComputeProof.sol

| Function | Description |
|---|---|
| `submitJob` | Submit a compute job with stake |
| `verifyComputation` | Verify with result and proof |
| `challengeResult` | Challenge with counter-proof |
| `resolveChallenge` | Arbiter resolves dispute |
| `finalizeJob` | Finalize after challenge period |

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
