import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TokenScorer with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const TokenScorer = await ethers.getContractFactory("TokenScorer");
  const tokenScorer = await TokenScorer.deploy();
  await tokenScorer.waitForDeployment();

  const address = await tokenScorer.getAddress();
  console.log("TokenScorer deployed to:", address);

  // Configure parameters
  const tx1 = await tokenScorer.setMinStake(ethers.parseEther("0.05"));
  await tx1.wait();
  console.log("Min auditor stake: 0.05 ETH");

  const tx2 = await tokenScorer.setMinBounty(ethers.parseEther("0.001"));
  await tx2.wait();
  console.log("Min bounty: 0.001 ETH");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
