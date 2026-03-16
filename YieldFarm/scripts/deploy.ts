import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying FarmManager with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const FarmManager = await ethers.getContractFactory("FarmManager");
  const farm = await FarmManager.deploy();
  await farm.waitForDeployment();

  const address = await farm.getAddress();
  console.log("FarmManager deployed to:", address);
  console.log("Owner:", await farm.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
