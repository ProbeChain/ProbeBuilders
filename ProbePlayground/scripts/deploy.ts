import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying PlaygroundRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const PlaygroundRegistry = await ethers.getContractFactory("PlaygroundRegistry");
  const registry = await PlaygroundRegistry.deploy();
  await registry.waitForDeployment();

  console.log("PlaygroundRegistry deployed to:", await registry.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
