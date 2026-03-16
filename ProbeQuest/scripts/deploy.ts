import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying RPGQuest with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const RPGQuest = await ethers.getContractFactory("RPGQuest");
  const rpgQuest = await RPGQuest.deploy({ value: ethers.parseEther("0.1") });
  await rpgQuest.waitForDeployment();

  const address = await rpgQuest.getAddress();
  console.log("RPGQuest deployed to:", address);

  // Create initial quests
  const tx1 = await rpgQuest.createQuest(
    "First Steps",
    "Complete your first training session",
    1, // difficulty
    50, // xpReward
    ethers.parseEther("0.001"), // tokenReward
    1, // minLevel
    0, // no prerequisite
    100 // maxCompletions
  );
  await tx1.wait();
  console.log("Quest 1 'First Steps' created");

  const tx2 = await rpgQuest.createQuest(
    "Dragon Slayer",
    "Defeat the ancient dragon in the caves",
    8, // difficulty
    500, // xpReward
    ethers.parseEther("0.01"), // tokenReward
    5, // minLevel
    1, // prerequisite: First Steps
    10 // maxCompletions
  );
  await tx2.wait();
  console.log("Quest 2 'Dragon Slayer' created");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
