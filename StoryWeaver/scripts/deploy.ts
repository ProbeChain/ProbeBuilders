import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying StoryEngine with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const StoryEngine = await ethers.getContractFactory("StoryEngine");
  const storyEngine = await StoryEngine.deploy();
  await storyEngine.waitForDeployment();

  const address = await storyEngine.getAddress();
  console.log("StoryEngine deployed to:", address);
  console.log("Default voting period:", (await storyEngine.defaultVotingPeriod()).toString(), "seconds");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
