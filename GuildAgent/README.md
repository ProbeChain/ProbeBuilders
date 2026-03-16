# GuildAgent

On-chain guild management with treasury voting and member roster on ProbeChain Rydberg Testnet.

## Features

- Create guilds with configurable entry fees
- Join/leave guilds with on-chain membership
- Treasury management via proposal voting
- 3-day voting period with majority rule
- Guild master role transfer
- Full member roster tracking

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: GuildManager

| Function | Description |
|---|---|
| `createGuild(name, entryFee)` | Create a new guild |
| `joinGuild(guildId)` | Join guild (payable) |
| `leaveGuild(guildId)` | Leave guild |
| `proposeTreasury(guildId, recipient, amount, desc)` | Propose treasury spend |
| `voteOnProposal(proposalId, support)` | Vote on proposal |
| `executeProposal(proposalId)` | Execute after voting ends |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
