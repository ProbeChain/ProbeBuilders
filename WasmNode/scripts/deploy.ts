import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying WasmExecutor with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const WasmExecutor = await ethers.getContractFactory("WasmExecutor");
  const executor = await WasmExecutor.deploy();
  await executor.waitForDeployment();

  const address = await executor.getAddress();
  console.log("WasmExecutor deployed to:", address);
  console.log("Min stake:", ethers.formatEther(await executor.minStake()), "ETH");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
