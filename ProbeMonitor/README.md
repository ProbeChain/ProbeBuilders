# ProbeMonitor

Node performance registry and monitoring with on-chain scoring on ProbeChain Rydberg Testnet.

## Features

- Register nodes with type (Validator, FullNode, LightNode, ArchiveNode, RPC)
- Report uptime and latency metrics
- Composite performance scoring (70% uptime, 30% latency)
- Authorized reporter system
- Performance leaderboard via score queries
- Full report history per node

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: NodeMonitor

| Function | Description |
|---|---|
| `registerNode(nodeId, endpoint, nodeType)` | Register a node |
| `reportUptime(nodeId, uptimePercent, blockHeight)` | Report uptime |
| `reportLatency(nodeId, avgMs)` | Report latency |
| `getNodeScore(nodeId)` | Get composite score |
| `setAuthorizedReporter(reporter, authorized)` | Manage reporters |
| `updateEndpoint(nodeId, newEndpoint)` | Update node endpoint |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
