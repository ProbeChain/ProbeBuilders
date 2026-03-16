import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ChessGame with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const ChessGame = await ethers.getContractFactory("ChessGame");
  const chess = await ChessGame.deploy();
  await chess.waitForDeployment();

  console.log("ChessGame deployed to:", await chess.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
