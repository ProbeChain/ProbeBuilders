# NPCStudio

NPC behavior registry and marketplace for game developers on ProbeChain Rydberg Testnet.

## Features

- Register NPCs with behavior scripts (IPFS), personality types, and game IDs
- Update NPC behavior on-chain with versioned hashes
- Paid interactions with NPCs (configurable fees)
- Rating system (1-5) requiring prior interaction
- Creator earnings with withdrawal and platform fee
- Browse NPCs by game or creator

## Contract: NPCRegistry.sol

| Function | Description |
|----------|-------------|
| `registerNPC(name, behaviorHash, personality, gameId, fee)` | Register a new NPC |
| `updateBehavior(npcId, newBehaviorHash)` | Update NPC behavior |
| `interactWithNPC(npcId)` | Interact with NPC (payable) |
| `rateNPC(npcId, score)` | Rate an NPC (1-5) |
| `withdrawEarnings(npcId)` | Creator withdraws earnings |

## Deployment

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
- **EVM:** London
