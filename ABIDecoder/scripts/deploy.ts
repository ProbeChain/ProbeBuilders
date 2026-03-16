import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ABIRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const ABIRegistry = await ethers.getContractFactory("ABIRegistry");
  const registry = await ABIRegistry.deploy();
  await registry.waitForDeployment();

  console.log("ABIRegistry deployed to:", await registry.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
