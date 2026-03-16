# CogitoNet

Decentralized knowledge graph network on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: KnowledgeGraph.sol

Build an on-chain knowledge graph with nodes, edges, path queries, and contributor rewards.

### Key Functions
- `addNode(label, dataHash, category)` -- Add a knowledge node
- `addEdge(fromNode, toNode, relationship)` -- Connect nodes with an edge
- `queryPath(startNode, endNode)` -- Find direct paths between nodes
- `rewardContributor()` -- Claim contribution rewards

### Deploy
```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
