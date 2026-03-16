import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GlossaryRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const GlossaryRegistry = await ethers.getContractFactory("GlossaryRegistry");
  const registry = await GlossaryRegistry.deploy();
  await registry.waitForDeployment();

  console.log("GlossaryRegistry deployed to:", await registry.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
