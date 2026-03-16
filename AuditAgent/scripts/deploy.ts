import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AuditRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const AuditRegistry = await ethers.getContractFactory("AuditRegistry");
  const registry = await AuditRegistry.deploy();
  await registry.waitForDeployment();

  console.log("AuditRegistry deployed to:", await registry.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
