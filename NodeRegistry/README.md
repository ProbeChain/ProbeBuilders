# NodeRegistry

Validator node registry for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: NodeRegistry.sol

Register Validator, Agent, and Physical nodes with stake, endpoint management, and slashing.

### Key Functions
- `registerNode(nodeType, endpoint)` — Register a node (payable stake)
- `updateNode(nodeId, newEndpoint)` — Update node endpoint
- `deregisterNode(nodeId)` — Deregister and unstake
- `getActiveNodes(nodeType)` — List active nodes by type
- `slash(nodeId, reason)` — Slash a misbehaving node (admin)

## Setup
```bash
npm install
cp .env.example .env
npx hardhat compile
npm run deploy
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
