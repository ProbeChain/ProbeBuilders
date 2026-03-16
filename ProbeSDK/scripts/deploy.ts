import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying SDKRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const SDKRegistry = await ethers.getContractFactory("SDKRegistry");
  const registry = await SDKRegistry.deploy();
  await registry.waitForDeployment();

  console.log("SDKRegistry deployed to:", await registry.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
