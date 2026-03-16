import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AIArena with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  // Use deployer as initial oracle
  const oracleAddress = deployer.address;

  const AIArena = await ethers.getContractFactory("AIArena");
  const aiArena = await AIArena.deploy(oracleAddress);
  await aiArena.waitForDeployment();

  const address = await aiArena.getAddress();
  console.log("AIArena deployed to:", address);
  console.log("Oracle set to:", oracleAddress);
  console.log("Initial ELO:", (await aiArena.INITIAL_ELO()).toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
