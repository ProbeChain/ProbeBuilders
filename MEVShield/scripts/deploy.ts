import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying PrivateMempool with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const PrivateMempool = await ethers.getContractFactory("PrivateMempool");
  const mempool = await PrivateMempool.deploy();
  await mempool.waitForDeployment();

  const address = await mempool.getAddress();
  console.log("PrivateMempool deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
