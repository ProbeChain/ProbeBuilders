# LootForge - Procedural Game Item Generation

ERC-721 NFT collection with procedurally generated game items featuring randomized attributes and rarity tiers on ProbeChain Rydberg Testnet.

## Features
- Mint items with pseudo-random attributes (attack, defense, speed, luck)
- Rarity tiers: Common, Rare, Epic, Legendary
- Equip/unequip system (one item per player)
- On-chain randomness from block hash + user seed
- Legendary items get stat boosts

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
