import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying InsightRegistry with account:", deployer.address);

  const platformFeeBps = 500; // 5%
  const Factory = await ethers.getContractFactory("InsightRegistry");
  const contract = await Factory.deploy(platformFeeBps);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("InsightRegistry deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
