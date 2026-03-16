# ProbeMetrics

Ecosystem health dashboard metrics on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: EcosystemMetrics.sol

Aggregate TVL, active users, TPS data across protocols to compute ecosystem health score.

### Key Functions
- `reportTVL(protocol, tvl)` -- Report protocol TVL
- `reportActiveUsers(protocol, count)` -- Report active user count
- `reportTPS(blockRange, avgTps)` -- Report TPS data
- `getEcosystemHealth()` -- Get aggregate health score

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
