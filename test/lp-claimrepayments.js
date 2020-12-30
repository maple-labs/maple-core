const { expect } = require("chai");
const { BigNumber } = require("ethers");
const artpath = "../../contracts/" + network.name + "/";

const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
const DAIABI = require(artpath + "abis/MintableTokenDAI.abi.js");
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");
const USDCABI = require(artpath + "abis/MintableTokenUSDC.abi.js");
const WETHAddress = require(artpath + "addresses/WETH9.address.js");
const WETHABI = require(artpath + "abis/WETH9.abi.js");
const WBTCAddress = require(artpath + "addresses/WBTC.address.js");
const WBTCABI = require(artpath + "abis/WBTC.abi.js");

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

const AmortizationRepaymentCalculator = require(artpath +
  "addresses/AmortizationRepaymentCalculator.address.js");
const BulletRepaymentCalculator = require(artpath +
  "addresses/BulletRepaymentCalculator.address.js");
const LateFeeNullCalculator = require(artpath +
  "addresses/LateFeeNullCalculator.address.js");
const PremiumFlatCalculator = require(artpath +
  "addresses/PremiumFlatCalculator.address.js");

describe("LiquidityPool claimRepayments", function () {
  let accounts;

  before(async () => {
    accounts = await ethers.provider.listAccounts();
  });

  let vaultAddress, abstractMinRaise;
  let collateralAssetSymbol, requestedAssetSymbol;

  it("A - Create amortization loan, get funded, draw down", async function () {
    WBTC = new ethers.Contract(
      WBTCAddress,
      WBTCABI,
      ethers.provider.getSigner(0)
    );

    const LoanVaultFactoryAddress = require(artpath +
      "addresses/LoanVaultFactory.address");
    const LoanVaultFactoryABI = require(artpath + "abis/LoanVaultFactory.abi");

    LoanVaultFactory = new ethers.Contract(
      LoanVaultFactoryAddress,
      LoanVaultFactoryABI,
      ethers.provider.getSigner(0)
    );

    const preIncrementorValue = await LoanVaultFactory.loanVaultsCreated();

    // ERC-20 contracts for tokens
    const REQUESTED_ASSET = DAIAddress; // Update symbol variable below when changing this.
    requestedAssetSymbol = "DAI";

    const COLLATERAL_ASSET = WBTCAddress; // Update symbol variable below when changing this.
    collateralAssetSymbol = "WBTC";

    const APR_BIPS = 1250; // 5%
    const TERM_DAYS = 270;
    const PAYMENT_INTERVAL_DAYS = 30;
    const ABSTRACT_AMOUNT_MIN_RAISE = 1000; // e.g. 1,000 DAI to raise
    abstractMinRaise = ABSTRACT_AMOUNT_MIN_RAISE;
    const MIN_RAISE = BigNumber.from(
      10 // Base 10
    )
      .pow(
        18 // Decimial precision of REQUEST_ASSET (DAI = 18, USDC = 6)
      )
      .mul(ABSTRACT_AMOUNT_MIN_RAISE);
    const COLLATERAL_BIPS_RATIO = 5000; // 50%
    const FUNDING_PERIOD_DAYS = 7;

    await LoanVaultFactory.createLoanVault(
      REQUESTED_ASSET,
      COLLATERAL_ASSET,
      [
        APR_BIPS,
        TERM_DAYS,
        PAYMENT_INTERVAL_DAYS,
        MIN_RAISE,
        COLLATERAL_BIPS_RATIO,
        FUNDING_PERIOD_DAYS,
      ],
      [
        AmortizationRepaymentCalculator,
        LateFeeNullCalculator,
        PremiumFlatCalculator,
      ],
      { gasLimit: 6000000 }
    );

    vaultAddress = await LoanVaultFactory.getLoanVault(preIncrementorValue);

    DAI_EXT_1 = new ethers.Contract(
      DAIAddress,
      DAIABI,
      ethers.provider.getSigner(1)
    );
    await DAI_EXT_1.mintSpecial(accounts[1], ABSTRACT_AMOUNT_MIN_RAISE);
    await DAI_EXT_1.approve(vaultAddress, MIN_RAISE);
    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );
    LoanVault2 = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(1)
    );
    const COLLATERAL_REQUIRED = await LoanVault.collateralRequiredForDrawdown(
      MIN_RAISE
    );

    // Fund loan for MIN_RAISE
    await LoanVault2.fundLoan(MIN_RAISE, accounts[1]);
    await WBTC.approve(
      vaultAddress,
      BigNumber.from(10)
        .pow(8)
        .mul(Math.round(parseInt(COLLATERAL_REQUIRED["_hex"]) / 10 ** 4))
        .mul(10000)
    );

    // Drawdown for the MIN_RAISE (assumes 18 decimal precision requestAsset).
    await LoanVault.drawdown(BigNumber.from(10).pow(18).mul(abstractMinRaise));

    PAYMENT_INFO = await LoanVault.getNextPayment();

    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));

    await DAI.approve(vaultAddress, PAYMENT_INFO[0]);
    await LoanVault.makePayment();

    PAYMENTS_REMAINING = await LoanVault.numberOfPayments();
    PAYMENTS_REMAINING = parseInt(PAYMENTS_REMAINING["_hex"]);

    while (PAYMENTS_REMAINING > 3) {
      PAYMENT_INFO = await LoanVault.getNextPayment();
      await DAI.approve(vaultAddress, PAYMENT_INFO[0]);
      await LoanVault.makePayment();
      PAYMENTS_REMAINING = await LoanVault.numberOfPayments();
      PAYMENTS_REMAINING = parseInt(PAYMENTS_REMAINING["_hex"]);
    }
  });
});
