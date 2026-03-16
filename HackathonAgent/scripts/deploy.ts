import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying HackathonManager with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const HackathonManager = await ethers.getContractFactory("HackathonManager");
  const manager = await HackathonManager.deploy();
  await manager.waitForDeployment();

  console.log("HackathonManager deployed to:", await manager.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
