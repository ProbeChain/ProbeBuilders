# ProbeScheduler2

Advanced task scheduler for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: AdvancedScheduler.sol

One-time and recurring task scheduling with keeper-based execution and payment.

### Key Functions
- `scheduleOnce(target, calldata, executeAfter)` — Schedule a one-time task
- `scheduleRecurring(target, calldata, interval, count)` — Schedule recurring execution
- `cancelSchedule(scheduleId)` — Cancel and refund remaining payment
- `executeSchedule(scheduleId)` — Execute a ready schedule (keeper)

## Setup
```bash
npm install
cp .env.example .env
npx hardhat compile
npm run deploy
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
