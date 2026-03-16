import { ethers } from "hardhat";

async function main() {
  const stake = ethers.parseEther("0.1"); // 0.1 PRB reporter stake

  console.log("Deploying OracleConsensus to Rydberg Testnet...");
  const OracleConsensus = await ethers.getContractFactory("OracleConsensus");
  const oracle = await OracleConsensus.deploy(stake);
  await oracle.waitForDeployment();

  const address = await oracle.getAddress();
  console.log(`OracleConsensus deployed at: ${address}`);
  console.log(`Reporter stake: ${ethers.formatEther(stake)} PRB`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
