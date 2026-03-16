# QuestBoard - Learn-to-Earn Quest System

On-chain quest platform with badge NFT rewards, proof verification, and learner reputation on ProbeChain Rydberg Testnet.

## Features
- Create quests with PROBE rewards and deadlines
- Multiple quest types: on-chain action, knowledge proof, community tasks, build challenges
- Submit proofs verified by trusted verifiers
- Badge NFTs awarded on completion
- Learner profiles with reputation tracking
- Max completions and deadline enforcement

## Deploy
```bash
npm install
cp .env.example .env  # add your private key
npx hardhat compile
npm run deploy
```

## Network
- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
