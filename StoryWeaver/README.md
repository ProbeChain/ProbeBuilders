# StoryWeaver

Interactive fiction engine with community-voted branching narratives on ProbeChain Rydberg Testnet.

## Features

- Create stories with IPFS-stored content
- Add branching choices at each story node
- Community voting on which branch to follow
- Configurable voting periods per story
- Automatic story advancement after voting period ends
- Track voter contributions across stories

## Contract: StoryEngine.sol

| Function | Description |
|----------|-------------|
| `createStory(title, openingHash)` | Create a new interactive story |
| `addBranch(storyId, parentNodeId, choiceText, contentHash)` | Add a story branch |
| `vote(storyId, branchId)` | Vote for a branch |
| `advanceStory(storyId)` | Advance to the winning branch |
| `endStory(storyId)` | End the story |

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
