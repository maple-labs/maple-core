const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const artpath = "../../contracts/" + network.name + "/";

const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
const DAIABI = require(artpath + "abis/MintableTokenDAI.abi.js");
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");
const USDCABI = require(artpath + "abis/MintableTokenUSDC.abi.js");
const MPLAddress = require(artpath + "addresses/MapleToken.address.js");
const MPLABI = require(artpath + "abis/MapleToken.abi.js");
const WETHAddress = require(artpath + "addresses/WETH9.address.js");
const WETHABI = require(artpath + "abis/WETH9.abi.js");
const WBTCAddress = require(artpath + "addresses/WBTC.address.js");
const WBTCABI = require(artpath + "abis/WBTC.abi.js");
const LVFactoryAddress = require(artpath +
  "addresses/LoanFactory.address.js");
const LVFactoryABI = require(artpath + "abis/LoanFactory.abi.js");
const FLFAddress = require(artpath +
  "addresses/FundingLockerFactory.address.js");
const FLFABI = require(artpath + "abis/FundingLockerFactory.abi.js");
const GlobalsAddress = require(artpath + "addresses/MapleGlobals.address.js");
const GlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
const LoanABI = require(artpath + "abis/Loan.abi.js");

const AmortizationRepaymentCalc = require(artpath +
  "addresses/AmortizationRepaymentCalc.address.js");
const BulletRepaymentCalc = require(artpath +
  "addresses/BulletRepaymentCalc.address.js");
const LateFeeCalc = require(artpath +
  "addresses/LateFeeCalc.address.js");
const PremiumFlatCalc = require(artpath +
  "addresses/PremiumFlatCalc.address.js");

describe("create 1000 DAI loan, fund 500 DAI, drawdown 20% wBTC collateralized loan", function () {
  const BUNK_ADDRESS = "0x0000000000000000000000000000000000000020";

  let DAI, USDC, MPL, WETH, WBTC;
  let LoanFactory, FundingLockerFactory, CollateralLockerFactory;
  let Globals, accounts;

  before(async () => {
    accounts = await ethers.provider.listAccounts();
    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));
    DAI_EXT_1 = new ethers.Contract(
      DAIAddress,
      DAIABI,
      ethers.provider.getSigner(1)
    );
    DAI_EXT_2 = new ethers.Contract(
      DAIAddress,
      DAIABI,
      ethers.provider.getSigner(2)
    );
    USDC = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(0)
    );
    MPL = new ethers.Contract(MPLAddress, MPLABI, ethers.provider.getSigner(0));
    WETH = new ethers.Contract(
      WETHAddress,
      WETHABI,
      ethers.provider.getSigner(0)
    );
    WBTC = new ethers.Contract(
      WBTCAddress,
      WBTCABI,
      ethers.provider.getSigner(0)
    );
    LoanFactory = new ethers.Contract(
      LVFactoryAddress,
      LVFactoryABI,
      ethers.provider.getSigner(0)
    );
    FundingLockerFactory = new ethers.Contract(
      FLFAddress,
      FLFABI,
      ethers.provider.getSigner(0)
    );
    Globals = new ethers.Contract(
      GlobalsAddress,
      GlobalsABI,
      ethers.provider.getSigner(0)
    );
  });

  let vaultAddress;

  it("createLoan(), requesting 1000 DAI", async function () {
    // Grab preIncrementor to get LoanID
    // Note: consider networkVersion=1 interactions w.r.t. async flow
    const preIncrementorValue = await LoanFactory.loansCreated();

    // 5% APR, 90 Day Term, 30 Day Interval, 1000 DAI, 20% Collateral, 7 Day Funding Period
    await LoanFactory.createLoan(
      DAIAddress,
      WBTCAddress,
      [500, 90, 30, BigNumber.from(10).pow(18).mul(1000), 2000, 7],
      [BulletRepaymentCalc, LateFeeCalc, PremiumFlatCalc]
    );

    vaultAddress = await LoanFactory.getLoan(preIncrementorValue);
  });

  it("fund loan for 500 DAI", async function () {
    await DAI_EXT_1.mintSpecial(accounts[1], 500);
    await DAI_EXT_1.approve(vaultAddress, BigNumber.from(10).pow(18).mul(500));

    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(1)
    );

    // Fund loan with 500 DAI
    await Loan.fundLoan(BigNumber.from(10).pow(18).mul(500), accounts[1]);
  });

  it("view collateral amount required", async function () {
    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(0)
    );

    const drawdownAmount_500DAI = await Loan.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(500)
    );

    // console.log(parseInt(drawdownAmount_500DAI["_hex"]))
  });

  xit("drawdown 500 DAI and commence the loan (failure)", async function () {
    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(0)
    );

    const drawdownAmount_500DAI = await Loan.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(500)
    );

    await WBTC.approve(
      vaultAddress,
      BigNumber.from(10)
        .pow(8)
        .mul(Math.round(parseInt(drawdownAmount_500DAI["_hex"]) / 10 ** 6))
        .mul(100)
    );

    await expect(
      Loan.drawdown(BigNumber.from(10).pow(18).mul(1000))
    ).to.be.revertedWith(
      "Loan::endFunding::ERR_DRAWDOWN_AMOUNT_ABOVE_FUNDING_LOCKER_BALANCE"
    );

    await expect(
      Loan.drawdown(BigNumber.from(10).pow(18).mul(500))
    ).to.be.revertedWith(
      "Loan::endFunding::ERR_DRAWDOWN_AMOUNT_BELOW_MIN_RAISE"
    );
  });

  it("fund 1000 more DAI", async function () {
    await DAI_EXT_1.mintSpecial(accounts[1], 1000);
    await DAI_EXT_1.approve(vaultAddress, BigNumber.from(10).pow(18).mul(1000));

    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(1)
    );

    // Fund loan with 1000 USDC
    await Loan.fundLoan(BigNumber.from(10).pow(18).mul(1000), accounts[1]);
  });

  it("drawdown 1000 DAI and commence loan", async function () {
    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(0)
    );

    const drawdownAmount_1000DAI = await Loan.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(1000)
    );

    await WBTC.approve(
      vaultAddress,
      BigNumber.from(10)
        .pow(8)
        .mul(Math.round(parseInt(drawdownAmount_1000DAI["_hex"]) / 10 ** 4))
        .mul(10000)
    );

    const PRE_LOCKER_BALANCE = await Loan.getFundingLockerBalance();
    const PRE_BORROWER_BALANCE = await DAI.balanceOf(accounts[0]);
    const PRE_LOANVAULT_BALANCE = await DAI.balanceOf(vaultAddress);

    await Loan.drawdown(BigNumber.from(10).pow(18).mul(1000));

    const POST_LOCKER_BALANCE = await Loan.getFundingLockerBalance();
    const POST_BORROWER_BALANCE = await DAI.balanceOf(accounts[0]);
    const POST_LOANVAULT_BALANCE = await DAI.balanceOf(vaultAddress);

    // Confirm the state of various contracts.

    const LoanState = await Loan.loanState();

    expect(LoanState).to.equals(1);

    // TODO: Implement handles for larger precisions (currently failing with 100mm+ DAI balance).
    expect(parseInt(POST_BORROWER_BALANCE["_hex"])).to.be.greaterThan(
      parseInt(PRE_BORROWER_BALANCE["_hex"])
    );

    // expect(
    //   parseInt(POST_BORROWER_BALANCE["_hex"]) - parseInt(PRE_BORROWER_BALANCE["_hex"])
    // ).to.be.greaterThan(parseInt(BigNumber.from(10).pow(18).mul(1000)["_hex"]));

    // expect(
    //   parseInt(PRE_LOCKER_BALANCE["_hex"]) - parseInt(POST_LOCKER_BALANCE["_hex"])
    // ).to.equals(parseInt(BigNumber.from(10).pow(18).mul(1500)["_hex"]));

    // expect(
    //   parseInt(POST_LOANVAULT_BALANCE["_hex"]) - parseInt(PRE_LOANVAULT_BALANCE["_hex"])
    // ).to.equals(parseInt(BigNumber.from(10).pow(18).mul(500)["_hex"]));
  });
});
