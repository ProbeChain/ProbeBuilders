import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying CardGame with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const CardGame = await ethers.getContractFactory("CardGame");
  const cardGame = await CardGame.deploy();
  await cardGame.waitForDeployment();

  const address = await cardGame.getAddress();
  console.log("CardGame deployed to:", address);

  // Set pack prices
  const tx = await cardGame.setPackPrices(
    ethers.parseEther("0.001"),
    ethers.parseEther("0.005")
  );
  await tx.wait();
  console.log("Pack prices set: basic=0.001 ETH, premium=0.005 ETH");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
