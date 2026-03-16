import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying SentimentOracle with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const SentimentOracle = await ethers.getContractFactory("SentimentOracle");
  const sentimentOracle = await SentimentOracle.deploy();
  await sentimentOracle.waitForDeployment();

  const address = await sentimentOracle.getAddress();
  console.log("SentimentOracle deployed to:", address);

  // Create initial feeds
  const tx1 = await sentimentOracle.createFeed(
    "ProbeChain Market Sentiment",
    "Overall market sentiment for ProbeChain ecosystem tokens"
  );
  await tx1.wait();
  console.log("Feed 1 'ProbeChain Market Sentiment' created");

  const tx2 = await sentimentOracle.createFeed(
    "DeFi Fear & Greed Index",
    "Aggregated fear and greed sentiment for DeFi protocols"
  );
  await tx2.wait();
  console.log("Feed 2 'DeFi Fear & Greed Index' created");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
