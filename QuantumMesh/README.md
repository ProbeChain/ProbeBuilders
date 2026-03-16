# QuantumMesh

Future compute capacity reservation on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: ComputeReservation.sol

Reserve, activate, cancel, and extend compute capacity for CPU, GPU, TPU, FPGA, and Quantum.

### Key Functions
- `reserveCapacity(computeType, amount, startDate, endDate)` payable -- Reserve capacity
- `activateReservation(reservationId)` -- Activate when start date arrives
- `cancelReservation(reservationId)` -- Cancel with partial refund
- `extendReservation(reservationId, newEndDate)` payable -- Extend duration

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
