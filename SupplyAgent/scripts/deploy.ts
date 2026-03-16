import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying SupplyChain with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const SupplyChain = await ethers.getContractFactory("SupplyChain");
  const supply = await SupplyChain.deploy();
  await supply.waitForDeployment();

  const address = await supply.getAddress();
  console.log("SupplyChain deployed to:", address);
  console.log("Owner:", await supply.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
