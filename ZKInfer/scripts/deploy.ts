import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ZKVerifier with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const Factory = await ethers.getContractFactory("ZKVerifier");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("ZKVerifier deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
