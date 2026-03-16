import { ethers } from "hardhat";

async function main() {
  const registrationFee = ethers.parseEther("0.01"); // 0.01 PRB

  console.log("Deploying AgentRegistry to Rydberg Testnet...");
  const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
  const registry = await AgentRegistry.deploy(registrationFee);
  await registry.waitForDeployment();

  const address = await registry.getAddress();
  console.log(`AgentRegistry deployed at: ${address}`);
  console.log(`Registration fee: ${ethers.formatEther(registrationFee)} PRB`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
