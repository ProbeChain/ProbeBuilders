import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying BridgeLock with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const BridgeLock = await ethers.getContractFactory("BridgeLock");
  const bridge = await BridgeLock.deploy();
  await bridge.waitForDeployment();

  const address = await bridge.getAddress();
  console.log("BridgeLock deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
