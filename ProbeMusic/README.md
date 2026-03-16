# ProbeMusic

Music rights management with per-stream micro-payments and royalty splits on ProbeChain Rydberg Testnet.

## Features

- **Track Registration** — Register tracks with ISRC codes, audio hashes, and configurable artist splits
- **Per-Stream Payments** — Micro-payment streaming with automatic split distribution
- **Royalty Collection** — Artists collect accumulated royalties on demand
- **Rights Transfer** — Transfer ownership shares between parties
- **ISRC Uniqueness** — Prevents duplicate track registration

## Contract: MusicRights.sol

| Function | Description |
|---|---|
| `registerTrack(title, audioHash, isrc, artists[], splits[])` | Register a new track |
| `streamTrack(trackId)` | Stream and pay for a track |
| `collectRoyalties(trackId)` | Collect accumulated royalties |
| `transferRights(trackId, share, newOwner)` | Transfer rights share |

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
- **EVM**: London
