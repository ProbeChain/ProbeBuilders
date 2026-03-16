# ProbeSpace

Decentralized forum on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Threads & Replies** — Create discussion threads with IPFS content hashes and reply to them.
- **Voting** — Upvote / downvote posts; karma is tracked per user.
- **Tipping** — Tip post authors with native tokens.
- **Moderation by Stakers** — Users who stake above the minimum threshold can moderate (soft-delete) content.
- **Pausable** — Owner can pause the contract in emergencies.

## Contract

`ForumContract.sol` — Solidity 0.8.24, EVM London, inline Ownable / ReentrancyGuard / Pausable.

## Quick Start

```bash
cp .env.example .env        # add your private key
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

| Parameter | Value |
|-----------|-------|
| Network   | ProbeChain Rydberg Testnet |
| RPC       | https://proscan.pro/chain/rydberg-rpc |
| Chain ID  | 8004 |
| EVM       | London |
