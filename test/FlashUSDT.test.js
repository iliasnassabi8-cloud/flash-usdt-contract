const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FlashUSDT Contract", function () {
  let flashUSDT;
  let owner;
  let admin;
  let trader;
  let user1;
  let user2;
  let tokenAddress;

  beforeEach(async function () {
    [owner, admin, trader, user1, user2, tokenAddress] = await ethers.getSigners();

    const FlashUSDT = await ethers.getContractFactory("FlashUSDT");
    flashUSDT = await FlashUSDT.deploy();
    await flashUSDT.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await flashUSDT.owner()).to.equal(owner.address);
    });

    it("Should have correct name and symbol", async function () {
      expect(await flashUSDT.name()).to.equal("Flash USDT");
      expect(await flashUSDT.symbol()).to.equal("fUSDT");
    });

    it("Should have initial supply assigned to owner", async function () {
      const ownerBalance = await flashUSDT.balanceOf(owner.address);
      expect(ownerBalance).to.equal(ethers.BigNumber.from("1000000000000000"));
    });
  });

  describe("Transfer Functions", function () {
    it("Should transfer tokens correctly", async function () {
      const transferAmount = ethers.utils.parseUnits("100", 6);
      await flashUSDT.transfer(user1.address, transferAmount);
      expect(await flashUSDT.balanceOf(user1.address)).to.equal(transferAmount);
    });

    it("Should reject transfer from frozen account", async function () {
      await flashUSDT.grantAdmin(admin.address);
      await flashUSDT.transfer(user1.address, ethers.utils.parseUnits("100", 6));
      await flashUSDT.connect(admin).freezeAccount(user1.address, "Testing");
      
      await expect(
        flashUSDT.connect(user1).transfer(user2.address, ethers.utils.parseUnits("50", 6))
      ).to.be.revertedWith("FlashUSDT: Account is frozen");
    });
  });

  describe("Swap Functions", function () {
    beforeEach(async function () {
      await flashUSDT.addSupportedToken(tokenAddress.address);
      await flashUSDT.setTokenPrice(tokenAddress.address, ethers.utils.parseEther("1"));
      await flashUSDT.transfer(user1.address, ethers.utils.parseUnits("1000", 6));
    });

    it("Should swap USDT for token", async function () {
      const amount = ethers.utils.parseUnits("100", 6);
      const balanceBefore = await flashUSDT.balanceOf(user1.address);
      
      await flashUSDT.connect(user1).swapUSDTForToken(tokenAddress.address, amount);
      
      const balanceAfter = await flashUSDT.balanceOf(user1.address);
      expect(balanceAfter).to.be.lessThan(balanceBefore);
    });
  });

  describe("Scheduled Transfer Functions", function () {
    beforeEach(async function () {
      await flashUSDT.transfer(user1.address, ethers.utils.parseUnits("1000", 6));
    });

    it("Should schedule a transfer", async function () {
      const amount = ethers.utils.parseUnits("100", 6);
      const duration = 30;
      
      await flashUSDT.connect(user1).scheduleTransfer(user2.address, amount, duration);
      
      const transfer = await flashUSDT.getScheduledTransfer(0);
      expect(transfer.from).to.equal(user1.address);
      expect(transfer.to).to.equal(user2.address);
      expect(transfer.amount).to.equal(amount);
    });

    it("Should reject transfer with invalid duration", async function () {
      const amount = ethers.utils.parseUnits("100", 6);
      const invalidDuration = 200;
      
      await expect(
        flashUSDT.connect(user1).scheduleTransfer(user2.address, amount, invalidDuration)
      ).to.be.revertedWith("FlashUSDT: Invalid duration");
    });
  });

  describe("Trading Functions", function () {
    beforeEach(async function () {
      await flashUSDT.grantTrader(trader.address);
      await flashUSDT.setTradingLimit(owner.address, ethers.utils.parseUnits("10000", 6));
      await flashUSDT.setTokenPrice(tokenAddress.address, ethers.utils.parseEther("1"));
      await flashUSDT.addSupportedToken(tokenAddress.address);
    });

    it("Should initiate a trade", async function () {
      const amountIn = ethers.utils.parseUnits("100", 6);
      const amountOut = ethers.utils.parseUnits("100", 6);
      const duration = 30;
      
      await flashUSDT.connect(trader).initiateTrade(
        owner.address,
        tokenAddress.address,
        amountIn,
        amountOut,
        duration
      );
      
      const trade = await flashUSDT.getTrade(0);
      expect(trade.trader).to.equal(trader.address);
      expect(trade.amountIn).to.equal(amountIn);
    });

    it("Should reject trade exceeding limit", async function () {
      await flashUSDT.setTradingLimit(owner.address, ethers.utils.parseUnits("50", 6));
      const amountIn = ethers.utils.parseUnits("100", 6);
      const amountOut = ethers.utils.parseUnits("100", 6);
      
      await expect(
        flashUSDT.connect(trader).initiateTrade(
          owner.address,
          tokenAddress.address,
          amountIn,
          amountOut,
          30
        )
      ).to.be.revertedWith("FlashUSDT: Amount exceeds trading limit");
    });
  });

  describe("Access Control", function () {
    it("Should grant and revoke admin privileges", async function () {
      await flashUSDT.grantAdmin(admin.address);
      expect(await flashUSDT.admins(admin.address)).to.be.true;
      
      await flashUSDT.revokeAdmin(admin.address);
      expect(await flashUSDT.admins(admin.address)).to.be.false;
    });

    it("Should grant and revoke trader privileges", async function () {
      await flashUSDT.grantAdmin(admin.address);
      await flashUSDT.connect(admin).grantTrader(trader.address);
      expect(await flashUSDT.traders(trader.address)).to.be.true;
      
      await flashUSDT.connect(admin).revokeTrader(trader.address);
      expect(await flashUSDT.traders(trader.address)).to.be.false;
    });

    it("Should prevent non-owner from granting admin", async function () {
      await expect(
        flashUSDT.connect(user1).grantAdmin(admin.address)
      ).to.be.revertedWith("FlashUSDT: Only owner can execute this");
    });
  });

  describe("Account Freezing", function () {
    beforeEach(async function () {
      await flashUSDT.grantAdmin(admin.address);
      await flashUSDT.transfer(user1.address, ethers.utils.parseUnits("1000", 6));
    });

    it("Should freeze and unfreeze accounts", async function () {
      await flashUSDT.connect(admin).freezeAccount(user1.address, "Testing freeze");
      expect(await flashUSDT.isFrozen(user1.address)).to.be.true;
      
      await flashUSDT.connect(admin).unfreezeAccount(user1.address);
      expect(await flashUSDT.isFrozen(user1.address)).to.be.false;
    });
  });

  describe("Token Management", function () {
    it("Should add and remove supported tokens", async function () {
      await flashUSDT.addSupportedToken(tokenAddress.address);
      expect(await flashUSDT.isSupportedToken(tokenAddress.address)).to.be.true;
      
      await flashUSDT.removeSupportedToken(tokenAddress.address);
      expect(await flashUSDT.isSupportedToken(tokenAddress.address)).to.be.false;
    });

    it("Should set and get token prices", async function () {
      const price = ethers.utils.parseEther("2.5");
      await flashUSDT.setTokenPrice(tokenAddress.address, price);
      expect(await flashUSDT.getTokenPrice(tokenAddress.address)).to.equal(price);
    });
  });
});
