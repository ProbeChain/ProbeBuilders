import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying PriceFeed with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const PriceFeed = await ethers.getContractFactory("PriceFeed");
  const feed = await PriceFeed.deploy();
  await feed.waitForDeployment();

  console.log("PriceFeed deployed to:", await feed.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
