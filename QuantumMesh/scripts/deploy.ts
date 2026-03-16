import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ComputeReservation with account:", deployer.address);

  const cancellationPenaltyBPS = 1000; // 10%
  const protocolFeeBPS = 200; // 2%

  const Factory = await ethers.getContractFactory("ComputeReservation");
  const contract = await Factory.deploy(cancellationPenaltyBPS, protocolFeeBPS);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("ComputeReservation deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
