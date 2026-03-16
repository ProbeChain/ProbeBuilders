import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AirdropDistributor with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const AirdropDistributor = await ethers.getContractFactory("AirdropDistributor");
  const distributor = await AirdropDistributor.deploy();
  await distributor.waitForDeployment();

  console.log("AirdropDistributor deployed to:", await distributor.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
