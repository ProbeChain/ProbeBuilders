import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GroupChat with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const Factory = await ethers.getContractFactory("GroupChat");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("GroupChat deployed to:", address);
  console.log("Chain ID: 8004 (ProbeChain Rydberg Testnet)");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
