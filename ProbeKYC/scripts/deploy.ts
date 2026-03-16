import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying KYCRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const KYCRegistry = await ethers.getContractFactory("KYCRegistry");
  const kyc = await KYCRegistry.deploy();
  await kyc.waitForDeployment();

  const address = await kyc.getAddress();
  console.log("KYCRegistry deployed to:", address);
  console.log("Owner:", await kyc.owner());
  console.log("Verifier count:", (await kyc.verifierCount()).toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
