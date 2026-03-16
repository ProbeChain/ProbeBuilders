import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying FanTokenFactory with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const FanTokenFactory = await ethers.getContractFactory("FanTokenFactory");
  const factory = await FanTokenFactory.deploy();
  await factory.waitForDeployment();

  console.log("FanTokenFactory deployed to:", await factory.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
