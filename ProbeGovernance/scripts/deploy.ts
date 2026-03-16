import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ProtocolGovernor with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const Factory = await ethers.getContractFactory("ProtocolGovernor");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("ProtocolGovernor deployed to:", address);
  console.log("Chain ID: 8004 (ProbeChain Rydberg Testnet)");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
