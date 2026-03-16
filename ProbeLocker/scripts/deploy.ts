import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TokenLocker with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const TokenLocker = await ethers.getContractFactory("TokenLocker");
  const locker = await TokenLocker.deploy();
  await locker.waitForDeployment();

  const address = await locker.getAddress();
  console.log("TokenLocker deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
