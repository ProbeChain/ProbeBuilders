import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying HiringPlatform with account:", deployer.address);

  const platformFeeBps = 300; // 3%
  const Factory = await ethers.getContractFactory("HiringPlatform");
  const contract = await Factory.deploy(platformFeeBps);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("HiringPlatform deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
