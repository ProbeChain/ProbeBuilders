import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying InvoiceFactoring with account:", deployer.address);

  const maxDiscountBPS = 3000; // 30%
  const platformFeeBPS = 200; // 2%
  const defaultPeriod = 7 * 86400; // 7 days

  const Factory = await ethers.getContractFactory("InvoiceFactoring");
  const contract = await Factory.deploy(maxDiscountBPS, platformFeeBPS, defaultPeriod);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("InvoiceFactoring deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
