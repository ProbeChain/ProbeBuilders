import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ItemMarket with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const ItemMarket = await ethers.getContractFactory("ItemMarket");
  const itemMarket = await ItemMarket.deploy();
  await itemMarket.waitForDeployment();

  const address = await itemMarket.getAddress();
  console.log("ItemMarket deployed to:", address);

  // Set platform fee to 2.5%
  const tx = await itemMarket.setFee(250);
  await tx.wait();
  console.log("Platform fee set to 2.5% (250 BPS)");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
