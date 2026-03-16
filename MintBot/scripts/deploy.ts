import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying MintAdvisor with account:", deployer.address);

  const Factory = await ethers.getContractFactory("MintAdvisor");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("MintAdvisor deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
