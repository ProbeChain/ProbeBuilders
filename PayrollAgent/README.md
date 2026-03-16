# PayrollAgent

Crypto payroll manager for ProbeChain Rydberg Testnet (Chain ID 8004).

## Contract: PayrollManager

- **addEmployee(address, salary, token, payFrequency)** — Register an employee.
- **processPayroll(employeeIds[])** — Batch-pay employees (native PROBE or ERC-20).
- **removeEmployee(employeeId)** — Deactivate an employee.
- **updateSalary(employeeId, newSalary)** — Adjust salary.
- Weekly, biweekly, or monthly pay frequencies. Multi-token support.

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```
