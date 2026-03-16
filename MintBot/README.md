# MintBot

Strategic minting advisor on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: MintAdvisor.sol

Register upcoming mints, analyze potential with scoring, set alerts, record results.

### Key Functions
- `registerUpcomingMint(collection, mintDate, price, supply)` -- Register a mint
- `analyzeMint(mintId)` -- Get analysis score and recommendation
- `setMintAlert(mintId)` -- Set alert for a mint
- `recordMintResult(mintId, result)` -- Record the mint outcome

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
