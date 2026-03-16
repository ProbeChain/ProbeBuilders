import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying NFTRental with account:", deployer.address);

  const feeBPS = 250; // 2.5%
  const lateReturnPenaltyBPS = 2000; // 20%
  const gracePeriod = 86400; // 1 day

  const Factory = await ethers.getContractFactory("NFTRental");
  const contract = await Factory.deploy(feeBPS, lateReturnPenaltyBPS, gracePeriod);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("NFTRental deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
