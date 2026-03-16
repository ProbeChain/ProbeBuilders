import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying DynamicAvatar with account:", deployer.address);

  const mintPrice = ethers.parseEther("0.01");
  const maxSupply = 10000;

  const Factory = await ethers.getContractFactory("DynamicAvatar");
  const contract = await Factory.deploy(mintPrice, maxSupply);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("DynamicAvatar deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
