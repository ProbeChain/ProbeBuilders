import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying LandValuation with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const LandValuation = await ethers.getContractFactory("LandValuation");
  const landValuation = await LandValuation.deploy();
  await landValuation.waitForDeployment();

  const address = await landValuation.getAddress();
  console.log("LandValuation deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
