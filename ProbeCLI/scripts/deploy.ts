import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ToolRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const ToolRegistry = await ethers.getContractFactory("ToolRegistry");
  const registry = await ToolRegistry.deploy();
  await registry.waitForDeployment();

  console.log("ToolRegistry deployed to:", await registry.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
