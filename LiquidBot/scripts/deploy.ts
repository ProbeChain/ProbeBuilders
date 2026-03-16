import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying LiquidationEngine with account:", deployer.address);

  const keeperReward = ethers.parseEther("0.01"); // 0.01 PROBE keeper reward
  const Factory = await ethers.getContractFactory("LiquidationEngine");
  const contract = await Factory.deploy(keeperReward);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("LiquidationEngine deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
