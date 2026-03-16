# IPChain

On-chain intellectual property registration, transfer, and licensing on ProbeChain Rydberg Testnet.

## Features

- **IP Registration** — Register patents, trademarks, copyrights, and trade secrets with content hashes
- **Ownership Transfer** — Transfer IP ownership with full on-chain history
- **Licensing** — Grant licenses with terms, fees, and expiration
- **Usage Tracking** — Record and verify IP usage with proof hashes
- **Duplicate Prevention** — Content hash uniqueness enforcement

## Contract: IPRegistry.sol

| Function | Description |
|---|---|
| `registerIP(title, contentHash, ipType, description)` | Register new intellectual property |
| `transferIP(ipId, newOwner)` | Transfer IP ownership |
| `licenseIP(ipId, licensee, terms, fee)` | Grant a license |
| `recordUsage(ipId, usageHash)` | Record IP usage |
| `revokeLicense(licenseId)` | Revoke an active license |

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
- **EVM**: London
