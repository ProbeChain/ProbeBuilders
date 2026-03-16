import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying CoverageProtocol with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const CoverageProtocol = await ethers.getContractFactory("CoverageProtocol");
  const protocol = await CoverageProtocol.deploy();
  await protocol.waitForDeployment();

  const address = await protocol.getAddress();
  console.log("CoverageProtocol deployed to:", address);
  console.log("Reward per user:", ethers.formatEther(await protocol.rewardPerUserServed()), "ETH");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
