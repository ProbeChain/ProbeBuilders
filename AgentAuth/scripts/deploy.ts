import { ethers } from "hardhat";

async function main() {
  console.log("Deploying AgentIdentity to Rydberg Testnet...");
  const AgentIdentity = await ethers.getContractFactory("AgentIdentity");
  const identity = await AgentIdentity.deploy();
  await identity.waitForDeployment();

  const address = await identity.getAddress();
  console.log(`AgentIdentity deployed at: ${address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
