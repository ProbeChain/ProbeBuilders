import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying CertificateRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const CertificateRegistry = await ethers.getContractFactory("CertificateRegistry");
  const registry = await CertificateRegistry.deploy();
  await registry.waitForDeployment();

  const address = await registry.getAddress();
  console.log("CertificateRegistry deployed to:", address);
  console.log("Name:", await registry.name());
  console.log("Symbol:", await registry.symbol());
  console.log("Owner:", await registry.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
