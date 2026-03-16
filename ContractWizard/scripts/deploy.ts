import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TemplateRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const TemplateRegistry = await ethers.getContractFactory("TemplateRegistry");
  const registry = await TemplateRegistry.deploy();
  await registry.waitForDeployment();

  console.log("TemplateRegistry deployed to:", await registry.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
