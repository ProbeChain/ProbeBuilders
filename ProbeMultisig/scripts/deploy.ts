import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying MultiSigWallet with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const owners = [deployer.address];
  const required = 1;

  const MultiSigWallet = await ethers.getContractFactory("MultiSigWallet");
  const wallet = await MultiSigWallet.deploy(owners, required);
  await wallet.waitForDeployment();

  const address = await wallet.getAddress();
  console.log("MultiSigWallet deployed to:", address);
  console.log("Owners:", owners);
  console.log("Required confirmations:", required);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
