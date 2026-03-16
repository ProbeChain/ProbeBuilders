import { ethers } from "hardhat";

async function main() {
  console.log("Deploying ModelBenchmark to ProbeChain Rydberg Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "PRB");

  const ModelBenchmark = await ethers.getContractFactory("ModelBenchmark");
  const benchmark = await ModelBenchmark.deploy();
  await benchmark.waitForDeployment();

  const address = await benchmark.getAddress();
  console.log("ModelBenchmark deployed to:", address);
  console.log("Min auditor stake:", ethers.formatEther(await benchmark.minAuditorStake()), "PRB");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
