import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying RaffleSystem with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const RaffleSystem = await ethers.getContractFactory("RaffleSystem");
  const raffle = await RaffleSystem.deploy();
  await raffle.waitForDeployment();

  const address = await raffle.getAddress();
  console.log("RaffleSystem deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
