import { ethers } from "hardhat";

async function main() {
  const messageFee = ethers.parseEther("0.001"); // 0.001 PRB per message

  console.log("Deploying AgentMessaging to Rydberg Testnet...");
  const AgentMessaging = await ethers.getContractFactory("AgentMessaging");
  const messaging = await AgentMessaging.deploy(messageFee);
  await messaging.waitForDeployment();

  const address = await messaging.getAddress();
  console.log(`AgentMessaging deployed at: ${address}`);
  console.log(`Message fee: ${ethers.formatEther(messageFee)} PRB`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
