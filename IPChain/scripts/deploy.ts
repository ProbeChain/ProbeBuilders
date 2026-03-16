import { ethers } from "hardhat";

async function main() {
  console.log("Deploying IPRegistry to ProbeChain Rydberg Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "PRB");

  const IPRegistry = await ethers.getContractFactory("IPRegistry");
  const registry = await IPRegistry.deploy();
  await registry.waitForDeployment();

  const address = await registry.getAddress();
  console.log("IPRegistry deployed to:", address);
  console.log("Registration fee:", ethers.formatEther(await registry.registrationFee()), "PRB");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
