import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AuctionHouse with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const AuctionHouse = await ethers.getContractFactory("AuctionHouse");
  const auction = await AuctionHouse.deploy();
  await auction.waitForDeployment();

  const address = await auction.getAddress();
  console.log("AuctionHouse deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
