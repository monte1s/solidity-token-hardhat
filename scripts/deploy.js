const { ethers } = require("hardhat");
const { Web3 } = require("web3");

const providerUrl = "http://127.0.0.1:8545";
const web3 = new Web3(providerUrl);

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // Deploy Mock USDC Token
  const USDC = await ethers.getContractFactory("ERC20Mock");
  const usdc = await USDC.deploy("USDC Token", "USDC");
  await usdc.waitForDeployment();
  console.log("USDC Token deployed at:", await usdc.getAddress());

  // Deploy Sale Token
  const SaleToken = await ethers.getContractFactory("ERC20Mock");
  const saleToken = await SaleToken.deploy("Sale Token", "SALE");
  await saleToken.waitForDeployment();
  console.log("Sale Token deployed at:", await saleToken.getAddress());

  // Deploy Token Sale Contract
  const TokenSale = await ethers.getContractFactory("TokenSale");

  const _usdcToken = await usdc.getAddress();
  const _saleToken = await saleToken.getAddress();
  const _depositAddress = deployer.address;
  const _kycSigner = deployer.address;
  const _tokenPriceETH = web3.utils.toWei("0.0001", "ether");

  const tokenSale = await TokenSale.deploy(
    _usdcToken,
    _saleToken,
    _depositAddress, // Deposit address
    _kycSigner, // KYC signer
    _tokenPriceETH // ETH price per token
  );
  await tokenSale.waitForDeployment();
  console.log("TokenSale deployed at:", await tokenSale.getAddress());
}

// Execute deployment script
main().catch((error) => {
  console.error(error);
  process.exit(1);
});
