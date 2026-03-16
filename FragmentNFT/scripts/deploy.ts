import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying NFTFragments with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const NFTFragments = await ethers.getContractFactory("NFTFragments");
  const fragments = await NFTFragments.deploy();
  await fragments.waitForDeployment();

  console.log("NFTFragments deployed to:", await fragments.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
