const { expect } = require("chai");
const { BigNumber } = require("ethers");
const artpath = "../../contracts/" + network.name + "/";

const AmortizationRepaymentCalc = require(artpath +
  "addresses/AmortizationRepaymentCalc.address.js");
const BulletRepaymentCalc = require(artpath +
  "addresses/BulletRepaymentCalc.address.js");
const LateFeeNullCalc = require(artpath +
  "addresses/LateFeeNullCalc.address.js");
const PremiumFlatCalc = require(artpath +
  "addresses/PremiumFlatCalc.address.js");

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
const DebtLockerFactoryAddress = require(artpath +
  "addresses/DebtLockerFactory.address.js");

const LPFactoryABI = require(artpath + "abis/PoolFactory.abi.js");
const LPFactoryAddress = require(artpath +
  "addresses/PoolFactory.address.js");
const PoolABI = require(artpath + "abis/Pool.abi.js");

const LVFactoryAddress = require(artpath +
  "addresses/LoanFactory.address.js");
const LVFactoryABI = require(artpath + "abis/LoanFactory.abi.js");
const LoanABI = require(artpath + "abis/Loan.abi.js");

describe("Pool & LiquidityLocker & StakeLocker", function () {
  let accounts;
  let LVFactory;
  let PoolFactory;
  let LVAddress;
  let DebtLocker;
  before(async () => {
    accounts = await ethers.provider.listAccounts();
  });

  xit("fundLoan() from liquidity pool", async function () {
    PoolFactory = new ethers.Contract(
      LPFactoryAddress,
      LPFactoryABI,
      ethers.provider.getSigner(0)
    );
    LPaddress = await PoolFactory.getPool(0);
    LP = new ethers.Contract(
      LPaddress,
      PoolABI,
      ethers.provider.getSigner(0)
    );
    LVFactory = new ethers.Contract(
      LVFactoryAddress,
      LVFactoryABI,
      ethers.provider.getSigner(0)
    );
    LVFactory.createLoan(
      DAIAddress,
      WETHAddress,
      [5000, 90, 1, 1000000000000, 0, 7],
      [
        AmortizationRepaymentCalc,
        LateFeeNullCalc,
        PremiumFlatCalc,
      ]
    );
    LVAddress = await LVFactory.getLoan(
      (await LVFactory.loanVaultsCreated()) - 1
    );
    await LP.fundLoan(LVAddress, DebtLockerFactoryAddress, 10);
    DebtLocker = await LP.loanTokenToLocker(LVAddress);
  });
  xit("make sure random guy cant call fundLoan in LP", async function () {
    LP = new ethers.Contract(
      LPaddress,
      PoolABI,
      ethers.provider.getSigner(1)
    );

    await expect(
      LP.fundLoan(LVAddress, DebtLockerFactoryAddress, 10)
    ).to.be.revertedWith("Pool:ERR_MSG_SENDER_NOT_DELEGATE");
  });
  xit("Check that loan tokens go to their respective locker", async function () {
    LP = new ethers.Contract(
      LPaddress,
      PoolABI,
      ethers.provider.getSigner(0)
    );

    Loan = new ethers.Contract(
      LVAddress,
      LoanABI,
      ethers.provider.getSigner(0)
    );
    const bal1 = await Loan.balanceOf(DebtLocker);
    await LP.fundLoan(LVAddress, DebtLockerFactoryAddress, 10);
    const bal2 = await Loan.balanceOf(DebtLocker);
    expect(bal2 - bal1 == 10);
  });
  xit("should not create new locker when one exists", async () => {
    await LP.fundLoan(LVAddress, DebtLockerFactoryAddress, 10);
    expect(await LP.loanTokenToLocker(LVAddress)).to.equal(DebtLocker);
  });
  xit("cant fund a random address", async () => {
    await expect(
      LP.fundLoan(accounts[5], DebtLockerFactoryAddress, 10)
    ).to.be.revertedWith("Pool::fundLoan:ERR_LOAN_VAULT_INVALID");
  });
});
