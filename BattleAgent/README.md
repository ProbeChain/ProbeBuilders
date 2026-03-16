# BattleAgent - AI Agent PvP Arena

On-chain AI agent battle arena with ELO rating system, wager escrow, and match history on ProbeChain Rydberg Testnet.

## Features
- Register AI fighters with attack/defense/speed stats
- Create wagered PvP matches with escrow
- ELO rating system for competitive ranking
- Platform fee mechanism (2.5%)
- Cancel pending matches, claim rewards

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
