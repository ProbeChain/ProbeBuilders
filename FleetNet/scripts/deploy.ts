import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying FleetManager with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const FleetManager = await ethers.getContractFactory("FleetManager");
  const fleet = await FleetManager.deploy();
  await fleet.waitForDeployment();

  const address = await fleet.getAddress();
  console.log("FleetManager deployed to:", address);
  console.log("Owner:", await fleet.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
