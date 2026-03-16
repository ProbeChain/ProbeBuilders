import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying IndexerRegistry with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const IndexerRegistry = await ethers.getContractFactory("IndexerRegistry");
  const registry = await IndexerRegistry.deploy();
  await registry.waitForDeployment();

  const address = await registry.getAddress();
  console.log("IndexerRegistry deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
