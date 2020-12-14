const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const artpath = '../../contracts/' + network.name + '/';

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
const LVFactoryAddress = require(artpath + "addresses/LoanVaultFactory.address.js");
const LVFactoryABI = require(artpath + "abis/LoanVaultFactory.abi.js");
const FLFAddress = require(artpath + "addresses/FundingLockerFactory.address.js");
const FLFABI = require(artpath + "abis/FundingLockerFactory.abi.js");
const GlobalsAddress = require(artpath + "addresses/MapleGlobals.address.js");
const GlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
const LoanVaultABI = require(artpath + "abis/LoanVault.abi.js");

describe("Calculator - Bullet Repayment", function () {

  const BUNK_ADDRESS = "0x0000000000000000000000000000000000000020";

  let DAI,USDC,MPL,WETH,WBTC;
  let LoanVaultFactory,FundingLockerFactory,CollateralLockerFactory;
  let Globals,accounts;

  before(async () => {
    accounts = await ethers.provider.listAccounts();
    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));
    DAI_EXT_1 = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(1));
    DAI_EXT_2 = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(2));
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
    LoanVaultFactory = new ethers.Contract(
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

  let vaultAddress, abstractMinRaise;
  let collateralAssetSymbol, requestedAssetSymbol;

  it("A - Issue and fund a bullet loan", async function () {

    const LoanVaultFactoryAddress = require(artpath + "addresses/LoanVaultFactory.address");
    const LoanVaultFactoryABI = require(artpath + "abis/LoanVaultFactory.abi");

    let LoanVaultFactory;

    LoanVaultFactory = new ethers.Contract(
      LoanVaultFactoryAddress,
      LoanVaultFactoryABI,
      ethers.provider.getSigner(0)
    );

    const preIncrementorValue = await LoanVaultFactory.loanVaultsCreated();

    // ERC-20 contracts for tokens
    const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address");
    const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address");
    const WETHAddress = require(artpath + "addresses/WETH9.address");
    const WBTCAddress = require(artpath + "addresses/WBTC.address");
    const ERC20ABI = require(artpath + "abis/MintableTokenDAI.abi");

    const REQUESTED_ASSET = DAIAddress; // Update symbol variable below when changing this.
    requestedAssetSymbol = 'DAI';

    const COLLATERAL_ASSET = WBTCAddress; // Update symbol variable below when changing this.
    collateralAssetSymbol = 'WBTC';

    const INTEREST_STRUCTURE = 'AMORTIZATION' // 'BULLET' or 'AMORTIZATION'

    const APR_BIPS = 1250; // 5%
    const TERM_DAYS = 90;
    const PAYMENT_INTERVAL_DAYS = 30;
    const ABSTRACT_AMOUNT_MIN_RAISE = 1000; // e.g. 1,000 DAI to raise
    abstractMinRaise = ABSTRACT_AMOUNT_MIN_RAISE;
    const MIN_RAISE = BigNumber.from(
      10 // Base 10
    ).pow(
      18 // Decimial precision of REQUEST_ASSET (DAI = 18, USDC = 6)
    ).mul(
      ABSTRACT_AMOUNT_MIN_RAISE
    );
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
        FUNDING_PERIOD_DAYS
      ],
      ethers.utils.formatBytes32String(INTEREST_STRUCTURE),
      {gasLimit: 6000000}
    );

    vaultAddress = await LoanVaultFactory.getLoanVault(preIncrementorValue);

    DAI = new ethers.Contract(DAIAddress, ERC20ABI, ethers.provider.getSigner(0));
    await DAI_EXT_1.mintSpecial(accounts[1], ABSTRACT_AMOUNT_MIN_RAISE)
    await DAI_EXT_1.approve(vaultAddress, MIN_RAISE)

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(1)
    );

    // Fund loan for MIN_RAISE
    await LoanVault.fundLoan(
      MIN_RAISE,
      accounts[1]
    )

  });

  it("B - Borrower draws down the loan", async function () {

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    // Fetch collateral amount required and approve loan vault.
    const MIN_RAISE = await LoanVault.minRaise();
    const COLLATERAL_REQUIRED = await LoanVault.collateralRequiredForDrawdown(MIN_RAISE);

    await WBTC.approve(
      vaultAddress,
      BigNumber.from(10).pow(8).mul(Math.round(parseInt(COLLATERAL_REQUIRED["_hex"]) / 10**4)).mul(10000)
    )

    // Drawdown for the MIN_RAISE (assumes 18 decimal precision requestAsset).
    await LoanVault.drawdown(
      BigNumber.from(10).pow(18).mul(abstractMinRaise)
    );

  });

  it("C - Test calculator for first repayment", async function () {

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const PAYMENT_INFO = await LoanVault.getNextPayment();

    // console.log(parseInt(PAYMENT_INFO[0]["_hex"])); // Total
    // console.log(parseInt(PAYMENT_INFO[1]["_hex"])); // Interest
    // console.log(parseInt(PAYMENT_INFO[2]["_hex"])); // Principal
    // console.log(parseInt(PAYMENT_INFO[3]["_hex"])); // Due By

    expect(true);

  });

});