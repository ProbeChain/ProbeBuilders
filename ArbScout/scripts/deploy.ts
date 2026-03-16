import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ArbExecutor with account:", deployer.address);

  const minProfitThreshold = ethers.parseEther("0.001"); // 0.001 tokens min profit

  const ArbExecutor = await ethers.getContractFactory("ArbExecutor");
  const arb = await ArbExecutor.deploy(minProfitThreshold);
  await arb.waitForDeployment();
  console.log("ArbExecutor deployed to:", await arb.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
