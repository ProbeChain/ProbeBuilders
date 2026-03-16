import { ethers } from "hardhat";

async function main() {
  console.log("Deploying BountyBoard to Rydberg Testnet...");
  const BountyBoard = await ethers.getContractFactory("BountyBoard");
  const bountyBoard = await BountyBoard.deploy();
  await bountyBoard.waitForDeployment();

  const address = await bountyBoard.getAddress();
  console.log(`BountyBoard deployed at: ${address}`);
  console.log(`Platform fee: 2%`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
