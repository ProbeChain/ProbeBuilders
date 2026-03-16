import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GuildManager with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const GuildManager = await ethers.getContractFactory("GuildManager");
  const guildManager = await GuildManager.deploy();
  await guildManager.waitForDeployment();

  console.log("GuildManager deployed to:", await guildManager.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
