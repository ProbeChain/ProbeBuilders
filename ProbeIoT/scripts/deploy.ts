import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying IoTRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const IoTRegistry = await ethers.getContractFactory("IoTRegistry");
  const registry = await IoTRegistry.deploy();
  await registry.waitForDeployment();

  const address = await registry.getAddress();
  console.log("IoTRegistry deployed to:", address);
  console.log("Owner:", await registry.owner());
  console.log("Total devices:", (await registry.totalDevices()).toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
