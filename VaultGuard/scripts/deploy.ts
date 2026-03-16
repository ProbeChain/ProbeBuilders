import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GuardedVault with account:", deployer.address);

  // Configure your 3 signers here:
  const signer1 = deployer.address;
  const signer2 = process.env.SIGNER2 || "0x0000000000000000000000000000000000000001";
  const signer3 = process.env.SIGNER3 || "0x0000000000000000000000000000000000000002";

  const GuardedVault = await ethers.getContractFactory("GuardedVault");
  const vault = await GuardedVault.deploy([signer1, signer2, signer3]);
  await vault.waitForDeployment();
  console.log("GuardedVault deployed to:", await vault.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
