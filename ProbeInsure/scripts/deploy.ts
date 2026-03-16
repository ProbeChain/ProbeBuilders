import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ParametricInsurance with account:", deployer.address);

  const Factory = await ethers.getContractFactory("ParametricInsurance");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("ParametricInsurance deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
