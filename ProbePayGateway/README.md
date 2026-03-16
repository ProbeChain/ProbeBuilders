# ProbePayGateway

Merchant payment gateway with invoice management for ProbeChain Rydberg Testnet (Chain ID 8004).

## Contract: InvoiceSystem

- **createInvoice(merchant, amount, token, dueDate, memo)** — Create a payment invoice.
- **payInvoice(invoiceId)** — Pay an invoice (native PROBE or ERC-20).
- **releaseInvoice(invoiceId)** — Release funds after confirmation period.
- **refundInvoice(invoiceId)** — Refund before release.
- Multi-token support, auto-release after confirmation period.

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```
