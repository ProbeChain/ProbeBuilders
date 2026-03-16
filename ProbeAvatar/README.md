# ProbeAvatar

Dynamic avatar NFTs that evolve on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: DynamicAvatar.sol (ERC-721)

Mint avatars with seeds, feed XP through on-chain activity, evolve through 6 stages.

### Key Functions
- `mintAvatar(seed)` payable -- Mint a new avatar
- `feedExperience(avatarId, activityType, amount)` -- Feed XP to avatar
- `evolveAvatar(avatarId)` -- Evolve when XP threshold met
- `getAvatarTraits(avatarId)` -- Get current trait values

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
