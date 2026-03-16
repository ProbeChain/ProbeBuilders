# CardForge - Trading Card Game

On-chain trading card game with pack minting, deck building, and wagered matches on ProbeChain Rydberg Testnet.

## Features

- **Pack Minting**: Basic and premium packs generate 5 random cards with rarity-weighted stats
- **Card Attributes**: Attack, defense, element (6 types), rarity (Common to Legendary)
- **Deck Building**: Create decks of 5 cards for competitive play
- **Wagered Matches**: Challenge other players' decks with native token wagers
- **Match Resolution**: Owner resolves matches; 2% fee on payouts

## Contract: CardGame.sol

| Function | Description |
|----------|-------------|
| `mintPack(packType)` | Buy a card pack (payable) |
| `createDeck(cardIds[5])` | Build a 5-card deck |
| `challengePlayer(deckId, opponentDeckId)` | Challenge with wager |
| `resolveMatch(matchId, winnerId)` | Resolve match (owner) |
| `cancelMatch(matchId)` | Cancel after 1 hour |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
