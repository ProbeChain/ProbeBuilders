import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AnalyticsRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const AnalyticsRegistry = await ethers.getContractFactory("AnalyticsRegistry");
  const registry = await AnalyticsRegistry.deploy();
  await registry.waitForDeployment();

  console.log("AnalyticsRegistry deployed to:", await registry.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
