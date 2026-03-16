import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying SurveillanceMarket with account:", deployer.address);

  const anomalyReward = ethers.parseEther("0.01");
  const feeBPS = 250; // 2.5%

  const Factory = await ethers.getContractFactory("SurveillanceMarket");
  const contract = await Factory.deploy(anomalyReward, feeBPS);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("SurveillanceMarket deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
