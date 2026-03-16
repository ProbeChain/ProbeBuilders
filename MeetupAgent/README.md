# MeetupAgent

On-chain event management on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Create Events** — Title, date, location, max attendees, ticket price.
- **Ticket Sales** — Attendees register and pay on-chain.
- **Check-in** — Organizer verifies attendee presence.
- **Cancel & Refund** — Cancel events with automatic refunds to all attendees.
- **Platform Fees** — Configurable fee on completed events.

## Contract

`EventManager.sol` — Solidity 0.8.24, EVM London, inline Ownable / ReentrancyGuard / Pausable.

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
