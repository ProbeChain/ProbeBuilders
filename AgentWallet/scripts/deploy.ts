import { ethers } from "hardhat";

async function main() {
  console.log("Deploying AgentWallet to Rydberg Testnet...");
  const AgentWallet = await ethers.getContractFactory("AgentWallet");
  const wallet = await AgentWallet.deploy();
  await wallet.waitForDeployment();

  const address = await wallet.getAddress();
  console.log(`AgentWallet deployed at: ${address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
