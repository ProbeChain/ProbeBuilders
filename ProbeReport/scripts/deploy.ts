import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ResearchNFT with account:", deployer.address);

  const feeBPS = 300; // 3%

  const Factory = await ethers.getContractFactory("ResearchNFT");
  const contract = await Factory.deploy(feeBPS);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("ResearchNFT deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
