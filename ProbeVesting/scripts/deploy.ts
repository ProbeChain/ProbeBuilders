import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying VestingContract with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const VestingContract = await ethers.getContractFactory("VestingContract");
  const vesting = await VestingContract.deploy();
  await vesting.waitForDeployment();

  const address = await vesting.getAddress();
  console.log("VestingContract deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
