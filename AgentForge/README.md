# AgentForge — Agent Registry & Lifecycle Management

On-chain registry for AI agents on ProbeChain Rydberg Testnet. Register agents with name, capabilities, and endpoint. Manage lifecycle states (Active/Paused/Deactivated) and track reputation scores.

## Contracts

- **AgentRegistry.sol** — Core registry with registration, updates, status management, pagination, and admin controls.

## Quick Start

```bash
npm install
cp .env.example .env   # add your private key
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Key Functions

| Function | Description |
|---|---|
| `registerAgent(name, capabilities, endpoint)` | Register a new agent (requires fee) |
| `updateAgent(agentId, name, capabilities, endpoint)` | Update agent metadata |
| `pauseAgent(agentId)` / `resumeAgent(agentId)` | Toggle agent status |
| `deactivateAgent(agentId)` | Permanently deactivate |
| `getAgent(agentId)` | Get agent details |
| `listAgents(offset, limit)` | Paginated agent list |

## Network

- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: `https://proscan.pro/chain/rydberg-rpc`
