import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying CredentialStack with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const Factory = await ethers.getContractFactory("CredentialStack");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("CredentialStack deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
