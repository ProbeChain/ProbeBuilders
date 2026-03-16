import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying RiskMonitor with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const RiskMonitor = await ethers.getContractFactory("RiskMonitor");
  const monitor = await RiskMonitor.deploy();
  await monitor.waitForDeployment();

  const address = await monitor.getAddress();
  console.log("RiskMonitor deployed to:", address);
  console.log("Owner:", await monitor.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
