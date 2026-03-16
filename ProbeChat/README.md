# ProbeChat

Pay-to-read encrypted messaging on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Send Encrypted Messages** — Attach an IPFS/Arweave hash and set a read fee.
- **Pay-to-Read** — Recipient pays the fee to unlock; fee goes to sender.
- **Delete** — Either party can soft-delete messages.
- **Platform Fees** — Configurable platform cut on read fees.

## Contract

`MessageEscrow.sol` — Solidity 0.8.24, EVM London, inline Ownable / ReentrancyGuard / Pausable.

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
