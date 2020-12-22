const { expect } = require("chai");
const { BigNumber } = require("ethers");
const artpath = "../../contracts/" + network.name + "/";

const DAIABI = require(artpath + "abis/MintableTokenDAI.abi.js");
const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
const USDCABI = require(artpath + "abis/MintableTokenUSDC.abi.js");
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");
const WETHAddress = require(artpath + "addresses/WETH9.address.js");

const MPLGlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
const MPLGlobalsAddress = require(artpath +
  "addresses/MapleGlobals.address.js");
const MapleGlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
const MapleGlobalsAddress = require(artpath +
  "addresses/MapleGlobals.address.js");
const LoanTokenLockerFactoryAddress = require(artpath +
  "addresses/LoanTokenLockerFactory.address.js");

const LPFactoryABI = require(artpath + "abis/LiquidityPoolFactory.abi.js");
const LPFactoryAddress = require(artpath +
  "addresses/LiquidityPoolFactory.address.js");
const LiquidityPoolABI = require(artpath + "abis/LiquidityPool.abi.js");

const LVFactoryAddress = require(artpath +
  "addresses/LoanVaultFactory.address.js");
const LVFactoryABI = require(artpath + "abis/LoanVaultFactory.abi.js");
const LoanVaultABI = require(artpath + "abis/LoanVault.abi.js");

describe("LiquidityPool & LiquidityLocker & StakeLocker", function () {
  let accounts;
  let LVFactory;
  let LiquidityPoolFactory;
  let LVAddress;
  let LoanTokenLocker;
  before(async () => {
    accounts = await ethers.provider.listAccounts();
  });

  it("fundLoan() from liquidity pool", async function () {
    LiquidityPoolFactory = new ethers.Contract(
      LPFactoryAddress,
      LPFactoryABI,
      ethers.provider.getSigner(0)
    );
    LPaddress = await LiquidityPoolFactory.getLiquidityPool(0);
    LP = new ethers.Contract(
      LPaddress,
      LiquidityPoolABI,
      ethers.provider.getSigner(0)
    );
    LVFactory = new ethers.Contract(
      LVFactoryAddress,
      LVFactoryABI,
      ethers.provider.getSigner(0)
    );
    LVFactory.createLoanVault(
      DAIAddress,
      WETHAddress,
      [5000, 90, 1, 1000000000000, 0, 7],
      [
        ethers.utils.formatBytes32String('AMORTIZATION'),
        ethers.utils.formatBytes32String('NULL'),
        ethers.utils.formatBytes32String('FLAT')
      ]
    );
    LVAddress = await LVFactory.getLoanVault(
      (await LVFactory.loanVaultsCreated()) - 1
    );
    await LP.fundLoan(LVAddress, LoanTokenLockerFactoryAddress, 10);
    LoanTokenLocker = await LP.loanTokenToLocker(LVAddress);
  });
  it("make sure random guy cant call fundLoan in LP", async function () {
    LP = new ethers.Contract(
      LPaddress,
      LiquidityPoolABI,
      ethers.provider.getSigner(1)
    );

    await expect(
      LP.fundLoan(LVAddress, LoanTokenLockerFactoryAddress, 10)
    ).to.be.revertedWith("LiquidityPool:ERR_MSG_SENDER_NOT_DELEGATE");
  });
  it("Check that loan tokens go to their respective locker", async function () {
    LP = new ethers.Contract(
      LPaddress,
      LiquidityPoolABI,
      ethers.provider.getSigner(0)
    );

    LoanVault = new ethers.Contract(
      LVAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );
    const bal1 = await LoanVault.balanceOf(LoanTokenLocker);
    await LP.fundLoan(LVAddress, LoanTokenLockerFactoryAddress, 10);
    const bal2 = await LoanVault.balanceOf(LoanTokenLocker);
    expect(bal2 - bal1 == 10);
  });
  it("should not create new locker when one exists", async () => {
    await LP.fundLoan(LVAddress, LoanTokenLockerFactoryAddress, 10);
    expect(await LP.loanTokenToLocker(LVAddress)).to.equal(LoanTokenLocker);
  });
  it("cant fund a random address", async () => {
    await expect(
      LP.fundLoan(accounts[5], LoanTokenLockerFactoryAddress, 10)
    ).to.be.revertedWith("LiquidityPool::fundLoan:ERR_LOAN_VAULT_INVALID");
  });
});
