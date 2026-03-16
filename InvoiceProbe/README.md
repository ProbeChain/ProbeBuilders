# InvoiceProbe

Decentralized invoice factoring on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: InvoiceFactoring.sol

Create invoices, sell to factors at discount, debtors settle, claim payments.

### Key Functions
- `createInvoice(debtor, amount, dueDate, documentHash)` -- Create an invoice
- `factorInvoice(invoiceId, discountBPS)` payable -- Factor buys at discount
- `settleInvoice(invoiceId)` payable -- Debtor settles the invoice
- `claimPayment()` -- Claim accumulated payments

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
