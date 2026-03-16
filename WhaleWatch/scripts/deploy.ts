import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying WhaleTracker with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const WhaleTracker = await ethers.getContractFactory("WhaleTracker");
  const whaleTracker = await WhaleTracker.deploy(ethers.parseEther("100")); // 100 ETH threshold
  await whaleTracker.waitForDeployment();

  const address = await whaleTracker.getAddress();
  console.log("WhaleTracker deployed to:", address);
  console.log("Alert threshold: 100 ETH");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
