const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");

const { ethers } = require("hardhat");

describe("Vault", function () {

  const rate = 50n; // 1 share = 50 tokens
  const managerFee = 100n; // 1 %
  const depositAmount = ethers.parseEther("10000");
  const BASIS_POINTS = 10000n;

  async function deployVaultFixture() {

    const [owner, user] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("ERC20Token");
    const token = await Token.deploy(owner.address);

    const Vault = await ethers.getContractFactory("Vault");
    const vault = await Vault.deploy(await token.getAddress(), rate, managerFee);

    await token.connect(owner).mint(user.address, depositAmount);
    await token.connect(owner).mint(owner.address, ethers.parseEther("1000000"));

    return { vault, token, owner, user };
  }

  describe("Deployment", function () {
    it("Should set the right toke", async function () {
      const { vault, token, owner, user } = await loadFixture(deployVaultFixture);

      expect(await vault.token()).to.equal(await token.getAddress());
    });

    it("Should set the right owner", async function () {
      const {  vault, token, owner, user } = await loadFixture(deployVaultFixture);

      expect(await vault.owner()).to.equal(owner.address);
      expect(await token.owner()).to.equal(owner.address);
    });
  });

  describe("Deposit", function () {
    describe("Validations", function () {
      it("Should revert if the amount is zero", async function () {
        const { vault } = await loadFixture(deployVaultFixture);

        await expect(vault.deposit(0)).to.be.revertedWithCustomError(vault, "AmountMustBeGreaterThanZero");
      });

      it("Should revert if the user has not approved the contract to spend the tokens", async function () {
        const { vault, token} = await loadFixture(deployVaultFixture);

        await expect(vault.deposit(depositAmount)).to.be.revertedWithCustomError(token, "ERC20InsufficientAllowance");
      });
    });

    describe("Events", function () {
      it("Should emit a Deposit event", async function () {
        const { vault, token, owner, user } = await loadFixture(deployVaultFixture);

        await token.connect(user).approve(await vault.getAddress(), depositAmount);
        await expect(vault.connect(user).deposit(depositAmount))
          .to.emit(vault, "Deposit")
          .withArgs(user.address, anyValue, anyValue, anyValue, anyValue);
      });

      it("Should emit a Withdrawal event", async function () {
        const { vault, token, owner, user } = await loadFixture(deployVaultFixture);

        await token.connect(user).approve(await vault.getAddress(), depositAmount);
        await vault.connect(user).deposit(depositAmount);

        const shares = await vault.userShares(user.address);

        await expect(vault.connect(user).withdraw(shares))
          .to.emit(vault, "Withdraw")
          .withArgs(user.address, anyValue, anyValue);
      });
    });

    describe("Vault Interest System", function () {
      it("Should calculate the correct amount of shares after deposit", async function () {
        const { vault, token, owner, user } = await loadFixture(deployVaultFixture);
  
        await token.connect(user).approve(await vault.getAddress(), depositAmount);
        await vault.connect(user).deposit(depositAmount);

        const shares = await vault.userShares(user.address);

        const adjustedDepositAmount = depositAmount - (depositAmount * managerFee / BASIS_POINTS);
        expect(shares).to.equal(adjustedDepositAmount / rate);
      });

      it("Should calculate the correct amount of tokens after withdrawal", async function () {
        const { vault, token, owner, user } = await loadFixture(deployVaultFixture);
  
        await token.connect(user).approve(await vault.getAddress(), depositAmount);
        await vault.connect(user).deposit(depositAmount);

        const shares = await vault.userShares(user.address);
        await vault.connect(user).withdraw(shares);

        const adjustedDepositAmount = depositAmount - (depositAmount * managerFee / BASIS_POINTS);
        expect(await token.balanceOf(user.address)).to.equal(adjustedDepositAmount);
      });

      it("Should add accomulated interest and update share rate", async function () {
        const { vault, token, owner, user } = await loadFixture(deployVaultFixture);
  
        await token.connect(user).approve(await vault.getAddress(), depositAmount);
        await vault.connect(user).deposit(depositAmount);

        const shares = await vault.userShares(user.address);
        
        // add to contract 10000 tokens
        const newTokens = ethers.parseEther("10000");
        await token.connect(owner).approve(await vault.getAddress(), newTokens);
        await vault.connect(owner).accumulateRewards(newTokens);

        const userShares = await vault.userShares(user.address);
        
        // withdraw all shares
        await vault.connect(user).withdraw(shares);

        // check if the user has received the correct amount of tokens
        const newRate = await vault.rate();
        const newAmount = userShares * newRate;
        expect(await token.balanceOf(user.address)).to.equal(newAmount);
      });
    });
  });
});
