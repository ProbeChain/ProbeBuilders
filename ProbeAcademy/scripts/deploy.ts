import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying CourseMarket with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const CourseMarket = await ethers.getContractFactory("CourseMarket");
  const market = await CourseMarket.deploy();
  await market.waitForDeployment();

  console.log("CourseMarket deployed to:", await market.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
