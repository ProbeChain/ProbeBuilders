import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying MineMonitor with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const MineMonitor = await ethers.getContractFactory("MineMonitor");
  const monitor = await MineMonitor.deploy();
  await monitor.waitForDeployment();

  const address = await monitor.getAddress();
  console.log("MineMonitor deployed to:", address);
  console.log("Total mines:", (await monitor.totalMines()).toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
