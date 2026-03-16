import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying InvoiceSystem with account:", deployer.address);

  const confirmationPeriod = 86400; // 24 hours
  const Factory = await ethers.getContractFactory("InvoiceSystem");
  const contract = await Factory.deploy(confirmationPeriod);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("InvoiceSystem deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
