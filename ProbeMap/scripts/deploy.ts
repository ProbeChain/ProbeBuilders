import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying MapContributions with account:", deployer.address);

  const rewardPerPOI = ethers.parseEther("0.005");
  const minVerifications = 3;

  const Factory = await ethers.getContractFactory("MapContributions");
  const contract = await Factory.deploy(rewardPerPOI, minVerifications);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("MapContributions deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
