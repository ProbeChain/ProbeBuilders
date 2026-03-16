# PropertyProbe

Real estate registry for ProbeChain Rydberg Testnet (Chain ID 8004).

## Contract: PropertyRegistry

- **registerProperty(propertyId, location, area, ownershipHash)** — Register a property on-chain.
- **transferTitle(propertyId, newOwner, notarySignature)** — Transfer ownership with notary verification.
- **addLien(propertyId, amount, description)** — Add a lien against a property.
- **removeLien(lienId)** — Satisfy and remove a lien.
- Full title chain history, authorized notary system.

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```
