import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AlertSubscription with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const AlertSubscription = await ethers.getContractFactory("AlertSubscription");
  const alertSubscription = await AlertSubscription.deploy();
  await alertSubscription.waitForDeployment();

  const address = await alertSubscription.getAddress();
  console.log("AlertSubscription deployed to:", address);

  // Set platform fee
  const tx = await alertSubscription.setPlatformFee(500); // 5%
  await tx.wait();
  console.log("Platform fee set to 5% (500 BPS)");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
