import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TimeLockController with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const minDelay = 3600; // 1 hour
  const maxDelay = 604800; // 1 week

  const TimeLockController = await ethers.getContractFactory("TimeLockController");
  const timelock = await TimeLockController.deploy(minDelay, maxDelay);
  await timelock.waitForDeployment();

  const address = await timelock.getAddress();
  console.log("TimeLockController deployed to:", address);
  console.log("Min delay:", minDelay, "seconds");
  console.log("Max delay:", maxDelay, "seconds");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
