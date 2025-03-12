const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { Web3 } = require("web3");
const CoreTokenABI =
  require("../artifacts/contracts/CoreToken.sol/CoreToken.json").abi;
const CoreTokenBytecode =
  require("../artifacts/contracts/CoreToken.sol/CoreToken.json").bytecode;

const ERC20MockABI =
  require("../artifacts/contracts/ERC20Mock.sol/ERC20Mock.json").abi;
const ERC20MockBytecode =
  require("../artifacts/contracts/ERC20Mock.sol/ERC20Mock.json").bytecode;

const TokenSaleABI =
  require("../artifacts/contracts/TokenSale.sol/TokenSale.json").abi;
const TokenSaleBytecode =
  require("../artifacts/contracts/TokenSale.sol/TokenSale.json").bytecode;

const providerUrl = "http://127.0.0.1:8545";
const web3 = new Web3(providerUrl);

describe("CoreToken", function () {
  let contractInstance;
  let accounts;

  const gasPriceGwei = "50";
  const gasPriceWei = web3.utils.toWei(gasPriceGwei, "gwei");

  async function deployCoreTokenContract() {
    accounts = await web3.eth.getAccounts();

    const user1 = web3.eth.accounts.create();
    const user2 = web3.eth.accounts.create();

    const owner = accounts[0];
    const coreTreasury = accounts[1];
    const treasurer = accounts[2];
    const vestingContract = accounts[6];
    const depositAddress = accounts[7];
    const kycSigner = accounts[8];

    await web3.eth.sendTransaction({
      from: treasurer,
      to: user1.address,
      value: web3.utils.toWei("1", "ether"),
    });

    await web3.eth.sendTransaction({
      from: treasurer,
      to: user2.address,
      value: web3.utils.toWei("2", "ether"),
    });

    const CoreToken = await new web3.eth.Contract(CoreTokenABI)
      .deploy({ data: CoreTokenBytecode, arguments: [owner, coreTreasury] })
      .send({ from: owner, gas: 10000000 });

    const usdcToken = await new web3.eth.Contract(ERC20MockABI)
      .deploy({ data: ERC20MockBytecode, arguments: ["USDC Token", "USDC"] })
      .send({ from: owner, gas: 10000000 });

    const saleContract = await new web3.eth.Contract(TokenSaleABI)
      .deploy({
        data: TokenSaleBytecode,
        arguments: [
          usdcToken.options.address,
          CoreToken.options.address,
          depositAddress,
          kycSigner,
          web3.utils.toWei("0.0001", "ether"),
        ],
      })
      .send({ from: owner, gas: 10000000 });

    contractInstance = CoreToken;

    return {
      coreToken: contractInstance,
      owner,
      coreTreasury,
      treasurer,
      user1,
      user2,
      saleContract,
      vestingContract,
      usdcToken,
      kycSigner,
    };
  }

  describe("Deployment", function () {
    it("Should deploy with correct initial supply and roles", async function () {
      const { coreToken, owner, coreTreasury } = await loadFixture(
        deployCoreTokenContract
      );

      const totalSupply = await coreToken.methods.totalSupply().call();
      expect(totalSupply).to.equal(web3.utils.toWei("850000000", "ether"));

      const treasuryBalance = await coreToken.methods
        .balanceOf(coreTreasury)
        .call();
      expect(treasuryBalance).to.equal(web3.utils.toWei("850000000", "ether"));

      const hasDefaultAdminRole = await coreToken.methods
        .hasRole(await coreToken.methods.DEFAULT_ADMIN_ROLE().call(), owner)
        .call();
      expect(hasDefaultAdminRole).to.be.true;
    });

    it("Should allow admin to set sale and vesting contracts", async function () {
      const { coreToken, owner, saleContract, vestingContract } =
        await loadFixture(deployCoreTokenContract);

      const saleAddress = saleContract.options.address;

      await coreToken.methods
        .setSaleContracts(saleAddress)
        .send({ from: owner });
      expect(await coreToken.methods.saleContract().call()).to.equal(
        saleAddress
      );

      await coreToken.methods
        .setVestContracts(vestingContract)
        .send({ from: owner });
      expect(await coreToken.methods.vestingContract().call()).to.equal(
        vestingContract
      );
    });

    it("Should allow admin to grant and revoke treasurer role", async function () {
      const { coreToken, owner, treasurer } = await loadFixture(
        deployCoreTokenContract
      );

      await coreToken.methods
        .setTreasurer(treasurer, true)
        .send({ from: owner });
      expect(
        await coreToken.methods
          .hasRole(await coreToken.methods.TREASURER().call(), treasurer)
          .call()
      ).to.be.true;

      await coreToken.methods
        .setTreasurer(treasurer, false)
        .send({ from: owner });
      expect(
        await coreToken.methods
          .hasRole(await coreToken.methods.TREASURER().call(), treasurer)
          .call()
      ).to.be.false;
    });

    it("Should allow treasury transfer to sale contract", async function () {
      const { coreToken, owner, treasurer, saleContract, coreTreasury } =
        await loadFixture(deployCoreTokenContract);

      const saleAddress = saleContract.options.address;

      await coreToken.methods
        .setSaleContracts(saleAddress)
        .send({ from: owner });
      await coreToken.methods
        .setTreasurer(treasurer, true)
        .send({ from: owner });

      await coreToken.methods
        .transferToSale(web3.utils.toWei("1000000", "ether"), coreTreasury)
        .send({ from: owner });
      expect(await coreToken.methods.balanceOf(saleAddress).call()).to.equal(
        web3.utils.toWei("1000000", "ether")
      );
    });

    it("Should allow burning of tokens", async function () {
      const { coreToken, owner, coreTreasury } = await loadFixture(
        deployCoreTokenContract
      );

      await coreToken.methods
        .burn(coreTreasury, web3.utils.toWei("1000000", "ether"))
        .send({ from: owner });
      expect(await coreToken.methods.totalSupply().call()).to.equal(
        web3.utils.toWei("849000000", "ether")
      );
    });

    it("Should allow user to register a key", async function () {
      const { coreToken, user1, kycSigner } = await loadFixture(
        deployCoreTokenContract
      );
      const messageHash = web3.utils.keccak256(kycSigner);
      const signature = user1.sign(messageHash);

      const signedTransactionUser1 = await web3.eth.accounts.signTransaction(
        {
          from: user1.address,
          to: coreToken.options.address,
          data: coreToken.methods
            .registerKey(messageHash, signature.signature)
            .encodeABI(),
          gas: 10000000,
          gasPrice: gasPriceWei,
        },
        user1.privateKey
      );

      await web3.eth.sendSignedTransaction(
        signedTransactionUser1.rawTransaction
      );

      expect(
        await coreToken.methods.registrationKeys(user1.address).call()
      ).to.equal(messageHash);
    });

    it("Should allow transfers for registered users", async function () {
      const { coreToken, user1, user2, coreTreasury } = await loadFixture(
        deployCoreTokenContract
      );

      await coreToken.methods
        .transfer(user1.address, web3.utils.toWei("1000", "ether"))
        .send({ from: coreTreasury });

      const signedTransactionUser1 = await web3.eth.accounts.signTransaction(
        {
          from: user1.address,
          to: coreToken.options.address,
          data: coreToken.methods
            .transfer(user2.address, web3.utils.toWei("500", "ether"))
            .encodeABI(),
          gas: 10000000,
          gasPrice: gasPriceWei,
        },
        user1.privateKey
      );

      await web3.eth.sendSignedTransaction(
        signedTransactionUser1.rawTransaction
      );

      expect(await coreToken.methods.balanceOf(user2.address).call()).to.equal(
        web3.utils.toWei("500", "ether")
      );
    });

    it("Should remove transfer restriction", async function () {
      const { coreToken, user1, user2, owner, coreTreasury } =
        await loadFixture(deployCoreTokenContract);

      await coreToken.methods.removeTransferRestriction().send({ from: owner });

      await coreToken.methods
        .transfer(user2.address, web3.utils.toWei("1", "ether"))
        .send({ from: coreTreasury });

      const signedTransactionUser1 = await web3.eth.accounts.signTransaction(
        {
          from: user2.address,
          to: coreToken.options.address,
          data: coreToken.methods
            .transfer(user1.address, web3.utils.toWei("1", "ether"))
            .encodeABI(),
          gas: 10000000,
          gasPrice: gasPriceWei,
        },
        user2.privateKey
      );

      await expect(
        web3.eth.sendSignedTransaction(signedTransactionUser1.rawTransaction)
      ).to.not.be.reverted;
    });

    it("Should start sale only by owner", async function () {
      const { saleContract, owner } = await loadFixture(
        deployCoreTokenContract
      );

      await saleContract.methods
        .startSale(Math.floor(Date.now() / 1000) + 1000)
        .send({ from: owner });

      // Listen for the "SaleStarted" event
      saleContract.events.SaleStarted({}, (error, event) => {
        if (error) {
          console.error(error);
        } else {
          console.log("Sale Started Event:", event);
        }
      });
    });

    it("Should allow user to buy tokens with ETH", async function () {
      const { saleContract, user1, coreToken, kycSigner } = await loadFixture(
        deployCoreTokenContract
      );

      const tokenPriceETH = web3.utils.toWei("0.0001", "ether");
      const buyAmountInETH = web3.utils.toWei("1", "ether"); // Buying with 1 ETH
      const expectedTokenAmount = buyAmountInETH / tokenPriceETH;

      // Sign the message for KYC
      const regKey = await coreToken.methods
        .registrationKeys(user1.address)
        .call();

      const messageHash = web3.utils.keccak256(kycSigner);
      const signature = user1.sign(messageHash);

      const message = await saleContract.methods
        .getMessageHash(messageHash)
        .call();

      console.log(message);

      const _is = await saleContract.methods
        .test(user1.address, regKey, signature.signature)
        .call();

      console.log(_is, kycSigner, user1.address);

      // Buy tokens using ETH
      // await saleContract.methods
      //   .buy(regKey, user1.address, 0, signature.signature) // `0` for USDC, since we're using ETH
      //   .send({
      //     from: user1.address,
      //     value: buyAmountInETH,
      //     gas: 10000000,
      //     gasPrice: gasPriceWei,
      //   });

      // // Check that the user's token balance increased
      // const userTokenBalance = await contractInstance.methods
      //   .balanceOf(user1.address)
      //   .call();
      // expect(Number(userTokenBalance)).to.equal(Number(expectedTokenAmount));

      // // Check that the total tokens sold has increased accordingly
      // const totalTokensSold = await saleContract.methods
      //   .totalTokensSold()
      //   .call();
      // expect(Number(totalTokensSold)).to.equal(Number(expectedTokenAmount));
    });

    // it("Should allow user to buy tokens with USDC", async function () {
    //   const { saleContract, user1, usdcToken, kycSigner } = await loadFixture(
    //     deployCoreTokenContract
    //   );

    //   const tokenPriceUSDC = 4e16; // $0.04 per token in USDC
    //   const buyAmountInUSDC = 100 * 1e6; // 100 USDC
    //   const expectedTokenAmount = (buyAmountInUSDC * 1e18) / tokenPriceUSDC;

    //   // Sign the message for KYC
    //   const regKey = web3.utils.keccak256(kycSigner);
    //   const messageHash = web3.utils.soliditySha3(regKey);
    //   const signature = await web3.eth.sign(messageHash, user1);

    //   // Approve the sale contract to spend USDC on behalf of the user
    //   await usdcToken.methods
    //     .approve(saleContract.options.address, buyAmountInUSDC)
    //     .send({ from: user1 });

    //   // Buy tokens using USDC
    //   await saleContract.methods
    //     .buy(regKey, user1.address, buyAmountInUSDC, signature) // 100 USDC
    //     .send({ from: user1.address, gas: 10000000, gasPrice: gasPriceWei });

    //   // Check that the user's token balance increased
    //   const userTokenBalance = await contractInstance.methods
    //     .balanceOf(user1.address)
    //     .call();
    //   expect(Number(userTokenBalance)).to.equal(Number(expectedTokenAmount));

    //   // Check that the total tokens sold has increased accordingly
    //   const totalTokensSold = await saleContract.methods
    //     .totalTokensSold()
    //     .call();
    //   expect(Number(totalTokensSold)).to.equal(Number(expectedTokenAmount));
    // });
  });
});
