import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying YieldVault with account:", deployer.address);

  // You must deploy or specify an ERC20 asset token first.
  // Replace with actual token address on Rydberg:
  const ASSET_TOKEN = process.env.ASSET_TOKEN || "0x0000000000000000000000000000000000000000";
  const DEPOSIT_CAP = ethers.parseEther("1000000"); // 1M tokens
  const PERFORMANCE_FEE_BPS = 1000; // 10%

  const YieldVault = await ethers.getContractFactory("YieldVault");
  const vault = await YieldVault.deploy(
    ASSET_TOKEN,
    "ProbeYield Vault",
    "pyVAULT",
    DEPOSIT_CAP,
    PERFORMANCE_FEE_BPS,
    deployer.address
  );
  await vault.waitForDeployment();
  console.log("YieldVault deployed to:", await vault.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
