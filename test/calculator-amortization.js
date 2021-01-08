const { expect, assert } = require("chai");
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

const AmortizationRepaymentCalc = require(artpath +
  "addresses/AmortizationRepaymentCalc.address.js");
const BulletRepaymentCalc = require(artpath +
  "addresses/BulletRepaymentCalc.address.js");
const LateFeeCalc = require(artpath +
  "addresses/LateFeeCalc.address.js");
const PremiumFlatCalc = require(artpath +
  "addresses/PremiumFlatCalc.address.js");

const LoanABI = require(artpath + "abis/Loan.abi.js");

describe("Calc - Amortization Repayment", function () {
  let accounts;

  before(async () => {
    accounts = await ethers.provider.listAccounts();
  });

  let vaultAddress, abstractMinRaise;
  let collateralAssetSymbol, requestedAssetSymbol;

  it("A - Issue and fund an amortization loan", async function () {
    const LoanFactoryAddress = require(artpath +
      "addresses/LoanFactory.address");
    const LoanFactoryABI = require(artpath + "abis/LoanFactory.abi");

    LoanFactory = new ethers.Contract(
      LoanFactoryAddress,
      LoanFactoryABI,
      ethers.provider.getSigner(0)
    );

    const preIncrementorValue = await LoanFactory.loansCreated();

    // ERC-20 contracts for tokens
    const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address");
    const USDCAddress = require(artpath +
      "addresses/MintableTokenUSDC.address");
    const WETHAddress = require(artpath + "addresses/WETH9.address");
    const WBTCAddress = require(artpath + "addresses/WBTC.address");
    const ERC20ABI = require(artpath + "abis/MintableTokenDAI.abi");

    const REQUESTED_ASSET = DAIAddress; // Update symbol variable below when changing this.
    requestedAssetSymbol = "DAI";

    const COLLATERAL_ASSET = WBTCAddress; // Update symbol variable below when changing this.
    collateralAssetSymbol = "WBTC";

    const APR_BIPS = 1250; // 5%
    const TERM_DAYS = 90;
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

    await LoanFactory.createLoan(
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
        AmortizationRepaymentCalc,
        LateFeeCalc,
        PremiumFlatCalc,
      ],
      { gasLimit: 6000000 }
    );

    vaultAddress = await LoanFactory.loans(preIncrementorValue);

    DAI_EXT_1 = new ethers.Contract(
      DAIAddress,
      DAIABI,
      ethers.provider.getSigner(1)
    );
    await DAI_EXT_1.mintSpecial(accounts[1], ABSTRACT_AMOUNT_MIN_RAISE);
    await DAI_EXT_1.approve(vaultAddress, MIN_RAISE);

    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(1)
    );

    // Fund loan for MIN_RAISE
    await Loan.fundLoan(MIN_RAISE, accounts[1]);
  });

  it("B - Borrower draws down the loan", async function () {
    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(0)
    );

    // Fetch collateral amount required and approve loan vault.
    const MIN_RAISE = await Loan.minRaise();
    const COLLATERAL_REQUIRED = await Loan.collateralRequiredForDrawdown(
      MIN_RAISE
    );

    WBTC = new ethers.Contract(
      WBTCAddress,
      WBTCABI,
      ethers.provider.getSigner(0)
    );

    await WBTC.approve(
      vaultAddress,
      BigNumber.from(10)
        .pow(8)
        .mul(Math.round(parseInt(COLLATERAL_REQUIRED["_hex"]) / 10 ** 4))
        .mul(10000)
    );

    // Drawdown for the MIN_RAISE (assumes 18 decimal precision requestAsset).
    await Loan.drawdown(BigNumber.from(10).pow(18).mul(abstractMinRaise));
  });

  it("C - Iterate through payments", async function () {
    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(0)
    );

    PAYMENT_INFO = await Loan.getNextPayment();

    // console.log(parseInt(PAYMENT_INFO[0]["_hex"])); // Total
    // console.log(parseInt(PAYMENT_INFO[1]["_hex"])); // Interest
    // console.log(parseInt(PAYMENT_INFO[2]["_hex"])); // Principal
    // console.log(parseInt(PAYMENT_INFO[3]["_hex"])); // Due By

    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));

    await DAI.approve(vaultAddress, PAYMENT_INFO[0]);
    await Loan.makePayment();

    PAYMENTS_REMAINING = await Loan.paymentsRemaining();
    PAYMENTS_REMAINING = parseInt(PAYMENTS_REMAINING["_hex"]);

    while (PAYMENTS_REMAINING > 0) {
      PAYMENT_INFO = await Loan.getNextPayment();
      await DAI.approve(vaultAddress, PAYMENT_INFO[0]);
      await Loan.makePayment();
      PAYMENTS_REMAINING = await Loan.paymentsRemaining();
      PAYMENTS_REMAINING = parseInt(PAYMENTS_REMAINING["_hex"]);
    }

    PAYMENTS_REMAINING = await Loan.paymentsRemaining();
    PRINCIPAL_OWED = await Loan.principalOwed();
    PAYMENTS_REMAINING = parseInt(PAYMENTS_REMAINING["_hex"]);
    PRINCIPAL_OWED = parseInt(PRINCIPAL_OWED["_hex"]);

    expect(PAYMENTS_REMAINING).to.equals(0);
    expect(PRINCIPAL_OWED).to.equals(0);
  });

  it("D - Test calculator for non 18-decimal precision, USDC(6)", async function () {
    // TODO: Identify the error raised in this test.

    const LoanFactoryAddress = require(artpath +
      "addresses/LoanFactory.address");
    const LoanFactoryABI = require(artpath + "abis/LoanFactory.abi");

    LoanFactory = new ethers.Contract(
      LoanFactoryAddress,
      LoanFactoryABI,
      ethers.provider.getSigner(0)
    );

    const preIncrementorValue = await LoanFactory.loansCreated();

    // ERC-20 contracts for tokens
    const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address");
    const USDCAddress = require(artpath +
      "addresses/MintableTokenUSDC.address");
    const WETHAddress = require(artpath + "addresses/WETH9.address");
    const WBTCAddress = require(artpath + "addresses/WBTC.address");
    const ERC20ABI = require(artpath + "abis/MintableTokenDAI.abi");

    const REQUESTED_ASSET = USDCAddress; // Update symbol variable below when changing this.
    requestedAssetSymbol = "USDC";

    const COLLATERAL_ASSET = WBTCAddress; // Update symbol variable below when changing this.
    collateralAssetSymbol = "WBTC";

    const APR_BIPS = 1250; // 12.5%
    const TERM_DAYS = 180;
    const PAYMENT_INTERVAL_DAYS = 30;
    const ABSTRACT_AMOUNT_MIN_RAISE = 50000; // Raising 50k USDC
    abstractMinRaise = ABSTRACT_AMOUNT_MIN_RAISE;
    const MIN_RAISE = BigNumber.from(
      10 // Base 10
    )
      .pow(
        6 // Decimial precision of REQUEST_ASSET (DAI = 18, USDC = 6)
      )
      .mul(ABSTRACT_AMOUNT_MIN_RAISE);
    const COLLATERAL_BIPS_RATIO = 2000; // 20%
    const FUNDING_PERIOD_DAYS = 7;

    await LoanFactory.createLoan(
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
        AmortizationRepaymentCalc,
        LateFeeCalc,
        PremiumFlatCalc,
      ],
      { gasLimit: 6000000 }
    );

    vaultAddress = await LoanFactory.loans(preIncrementorValue);

    USDC_EXT_1 = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(1)
    );
    await USDC_EXT_1.mintSpecial(accounts[1], ABSTRACT_AMOUNT_MIN_RAISE);
    await USDC_EXT_1.approve(vaultAddress, MIN_RAISE);

    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(1) // getSigner(1) == Lender
    );

    // Fund loan for MIN_RAISE
    await Loan.fundLoan(MIN_RAISE, accounts[1]);

    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(0) // getSigner(0) == Borrower
    );

    // Fetch collateral amount required and approve loan vault.
    const MIN_RAISE_ONCHAIN = await Loan.minRaise();
    const COLLATERAL_REQUIRED = await Loan.collateralRequiredForDrawdown(
      MIN_RAISE_ONCHAIN
    );

    WBTC = new ethers.Contract(
      WBTCAddress,
      WBTCABI,
      ethers.provider.getSigner(0)
    );

    await WBTC.approve(
      vaultAddress,
      BigNumber.from(10)
        .pow(8)
        .mul(Math.round(parseInt(COLLATERAL_REQUIRED["_hex"]) / 10 ** 4))
        .mul(10000)
    );

    // Drawdown for the MIN_RAISE, pow(6) is USDC decimal precision
    await Loan.drawdown(MIN_RAISE);

    // Make first payment.
    USDC = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(0)
    );

    PAYMENT_INFO = await Loan.getNextPayment();
    await USDC.approve(vaultAddress, PAYMENT_INFO[0]);
    await Loan.makePayment();

    // Make remaining payments.
    PAYMENTS_REMAINING = await Loan.paymentsRemaining();
    PAYMENTS_REMAINING = parseInt(PAYMENTS_REMAINING["_hex"]);

    while (PAYMENTS_REMAINING > 0) {
      PAYMENT_INFO = await Loan.getNextPayment();
      await USDC.approve(vaultAddress, PAYMENT_INFO[0]);
      await Loan.makePayment();
      PAYMENTS_REMAINING = await Loan.paymentsRemaining();
      PAYMENTS_REMAINING = parseInt(PAYMENTS_REMAINING["_hex"]);
    }

    PAYMENTS_REMAINING = await Loan.paymentsRemaining();
    PRINCIPAL_OWED = await Loan.principalOwed();
    PAYMENTS_REMAINING = parseInt(PAYMENTS_REMAINING["_hex"]);
    PRINCIPAL_OWED = parseInt(PRINCIPAL_OWED["_hex"]);

    expect(PAYMENTS_REMAINING).to.equals(0);
    expect(PRINCIPAL_OWED).to.equals(0);
  });
});
