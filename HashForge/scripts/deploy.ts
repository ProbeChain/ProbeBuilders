import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ComputeProof with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const ComputeProof = await ethers.getContractFactory("ComputeProof");
  const proof = await ComputeProof.deploy();
  await proof.waitForDeployment();

  const address = await proof.getAddress();
  console.log("ComputeProof deployed to:", address);
  console.log("Min stake:", ethers.formatEther(await proof.minStake()), "ETH");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
