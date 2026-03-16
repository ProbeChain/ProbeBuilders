# ProbeSwarm

Multi-agent swarm coordination on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: SwarmCoordinator.sol

Register multi-agent swarms, assign subtasks, report completions, and finalize swarm operations.

### Key Functions
- `registerSwarm(agents[], taskHash)` -- Register a new agent swarm
- `assignTask(swarmId, agentId, subtaskHash)` -- Assign subtask to an agent
- `reportCompletion(swarmId, subtaskId, resultHash)` -- Agent reports subtask done
- `finalizeSwarm(swarmId)` -- Finalize the swarm operation

### Deploy
```bash
cp .env.example .env  # add your private key
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
