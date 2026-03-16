import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TaxLedger with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const TaxLedger = await ethers.getContractFactory("TaxLedger");
  const ledger = await TaxLedger.deploy();
  await ledger.waitForDeployment();

  const address = await ledger.getAddress();
  console.log("TaxLedger deployed to:", address);
  console.log("Owner:", await ledger.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
