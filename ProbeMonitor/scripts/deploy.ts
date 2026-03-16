import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying NodeMonitor with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const NodeMonitor = await ethers.getContractFactory("NodeMonitor");
  const monitor = await NodeMonitor.deploy();
  await monitor.waitForDeployment();

  console.log("NodeMonitor deployed to:", await monitor.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
