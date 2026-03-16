# AgentSandbox

Agent testing sandbox for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: SandboxEnvironment.sol

Provides isolated sandboxes where AI agents can be tested before production deployment.

### Key Functions
- `createSandbox(agentId, config)` — Create a new testing sandbox for an agent
- `executeInSandbox(sandboxId, actionData)` — Execute an action inside a sandbox
- `getSandboxState(sandboxId)` — Get the current state of a sandbox
- `scoreBehavior(sandboxId)` — Score the behavior of an agent
- `promoteToProd(sandboxId)` — Promote a tested agent to production

## Setup
```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
