import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GaslessRelay with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const GaslessRelay = await ethers.getContractFactory("GaslessRelay");
  const relay = await GaslessRelay.deploy();
  await relay.waitForDeployment();

  console.log("GaslessRelay deployed to:", await relay.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
