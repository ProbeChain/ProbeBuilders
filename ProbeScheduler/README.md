# ProbeScheduler

Decentralized cron job scheduler on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: CronScheduler.sol

Create recurring jobs, keepers execute for rewards, pause/cancel jobs with deposit refunds.

### Key Functions
- `createJob(target, calldata, interval, startTime, maxExecutions)` payable -- Create a job
- `executeJob(jobId)` -- Keeper executes a due job
- `pauseJob(jobId)` -- Pause a job
- `cancelJob(jobId)` -- Cancel and refund remaining deposit

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
