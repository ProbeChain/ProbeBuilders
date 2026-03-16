# PetChain - Digital Pet with Evolution

ERC-721 digital pet system with feeding, training, evolution, and time-based stat decay on ProbeChain Rydberg Testnet.

## Features

- **Pet Adoption**: Mint ERC-721 pets from 5 species (Cat, Dog, Dragon, Phoenix, Unicorn) with unique base stats
- **Feeding System**: Feed pets to reduce hunger and boost happiness; stats decay over time if neglected
- **Training**: Train 4 skills (Speed, Power, Wisdom, Endurance) with cooldowns; earns XP
- **Evolution**: 4 stages (Baby, Juvenile, Adult, Mythic) unlocked at levels 5, 15, and 30
- **Time Decay**: Hunger increases and happiness decreases every hour automatically

## Contract: DigitalPet.sol

| Function | Description |
|----------|-------------|
| `adoptPet(species, name)` | Mint a new pet (payable) |
| `feedPet(petId)` | Feed to reduce hunger |
| `trainPet(petId, skill)` | Train a skill for XP |
| `evolvePet(petId)` | Evolve when conditions met |
| `getPetStats(petId)` | View live stats with decay |

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
