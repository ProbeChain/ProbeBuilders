import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying MEVRegistry with account:", deployer.address);

  const minStake = ethers.parseEther("0.1");       // 0.1 PROBE
  const reportReward = ethers.parseEther("0.005");  // 0.005 PROBE per report
  const slashPenalty = ethers.parseEther("0.05");   // 0.05 PROBE slash

  const Factory = await ethers.getContractFactory("MEVRegistry");
  const contract = await Factory.deploy(minStake, reportReward, slashPenalty);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("MEVRegistry deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
