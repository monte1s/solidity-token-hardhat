const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { Web3 } = require("web3");
const CoreTokenABI =
  require("../artifacts/contracts/CoreToken.sol/CoreToken.json").abi;
const CoreTokenBytecode =
  require("../artifacts/contracts/CoreToken.sol/CoreToken.json").bytecode;

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
    const saleContract = accounts[5];
    const vestingContract = accounts[6];

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

      await coreToken.methods
        .setSaleContracts(saleContract)
        .send({ from: owner });
      expect(await coreToken.methods.saleContract().call()).to.equal(
        saleContract
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

      await coreToken.methods
        .setSaleContracts(saleContract)
        .send({ from: owner });
      await coreToken.methods
        .setTreasurer(treasurer, true)
        .send({ from: owner });

      await coreToken.methods
        .transferToSale(web3.utils.toWei("1000000", "ether"), coreTreasury)
        .send({ from: owner });
      expect(await coreToken.methods.balanceOf(saleContract).call()).to.equal(
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
      const { coreToken, user1 } = await loadFixture(deployCoreTokenContract);
      const message = "Hello, Ethereum!";
      const messageHash = web3.utils.keccak256(message);
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
  });
});
