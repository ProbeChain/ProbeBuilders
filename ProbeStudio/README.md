# ProbeStudio

Creator workspace with collaboration and revenue splitting on ProbeChain Rydberg Testnet.

## Features

- **Project Management** — Create collaborative projects with different types (Art, Music, Writing, Code, Video, Mixed)
- **Collaborator System** — Add collaborators with configurable revenue share (basis points)
- **Work Publishing** — Publish works with content hashes and set sale prices
- **Purchase & Access** — Users purchase works with on-chain payment tracking
- **Revenue Distribution** — Automatic revenue splitting among all collaborators based on shares
- **Platform Fee** — Configurable platform fee (default 2.5%)

## Contract: CreatorStudio.sol

| Function | Description |
|---|---|
| `createProject(name, type)` | Create a new collaborative project |
| `addCollaborator(projectId, collaborator, revenueShare)` | Add collaborator with revenue share |
| `publishWork(projectId, contentHash, price)` | Publish a work for sale |
| `purchaseWork(workId)` | Purchase a published work |
| `distributeRevenue(workId)` | Distribute revenue to collaborators |

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
