# ProbeRandom

Verifiable randomness oracle for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: RandomnessOracle.sol

VRF-like request-fulfill pattern with proof verification and consumer callbacks.

### Key Functions
- `requestRandom(seed, callbackContract)` — Request a random number
- `fulfillRandom(requestId, randomValue, proof)` — Fulfill with proof (oracle)
- `getRandomResult(requestId)` — Get the random result

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
