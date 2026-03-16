import { ethers } from "hardhat";

async function main() {
  console.log("Deploying GovernorAgent to Rydberg Testnet...");
  const GovernorAgent = await ethers.getContractFactory("GovernorAgent");
  const governor = await GovernorAgent.deploy();
  await governor.waitForDeployment();

  const address = await governor.getAddress();
  console.log(`GovernorAgent deployed at: ${address}`);
  console.log(`Voting period: 3 days`);
  console.log(`Timelock delay: 1 day`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
