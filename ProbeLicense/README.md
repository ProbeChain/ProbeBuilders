# ProbeLicense

Software license management with on-chain issuance, verification, and renewal on ProbeChain Rydberg Testnet.

## Features

- **Product Registration** — Vendors create products with name and description
- **License Issuance** — Issue Perpetual, Subscription, or Trial licenses with payment
- **On-Chain Verification** — Verify license validity at any time (auto-expiration support)
- **License Renewal** — Extend subscription licenses with payment
- **Revocation** — Vendors can revoke licenses
- **Platform Fees** — Configurable platform fee on license sales

## Contract: LicenseManager.sol

| Function | Description |
|---|---|
| `createProduct(name, description)` | Create a software product |
| `issueLicense(productId, licensee, type, duration, price)` | Issue a license |
| `verifyLicense(licenseId)` | Verify license validity |
| `revokeLicense(licenseId)` | Revoke a license |
| `renewLicense(licenseId, duration)` | Renew a subscription |

## License Types

- **Perpetual** — Never expires
- **Subscription** — Time-limited, renewable
- **Trial** — Time-limited (max 30 days), non-renewable

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
