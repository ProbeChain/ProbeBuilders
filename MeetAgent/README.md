# MeetAgent

Professional networking protocol on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Skill-based Profiles** — Register skills and interests on-chain.
- **Connections** — Request, accept, or reject connections.
- **Endorsements** — Connected users endorse each other's skills.
- **Matching** — Find users who share skills or interests.

## Contract

`NetworkingProtocol.sol` — Solidity 0.8.24, EVM London, inline Ownable / ReentrancyGuard / Pausable.

## Quick Start

```bash
cp .env.example .env
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
