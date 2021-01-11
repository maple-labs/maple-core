const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const artpath = "../../contracts/" + network.name + "/";

const DAIAddress       = require(artpath + "addresses/MintableTokenDAI.address.js");
const DAIABI           = require(artpath + "abis/MintableTokenDAI.abi.js");
const USDCAddress      = require(artpath + "addresses/MintableTokenUSDC.address.js");
const USDCABI          = require(artpath + "abis/MintableTokenUSDC.abi.js");
const MPLAddress       = require(artpath + "addresses/MapleToken.address.js");
const MPLABI           = require(artpath + "abis/MapleToken.abi.js");
const WETHAddress      = require(artpath + "addresses/WETH9.address.js");
const WETHABI          = require(artpath + "abis/WETH9.abi.js");
const WBTCAddress      = require(artpath + "addresses/WBTC.address.js");
const WBTCABI          = require(artpath + "abis/WBTC.abi.js");
const LVFactoryAddress = require(artpath + "addresses/LoanFactory.address.js");
const LVFactoryABI     = require(artpath + "abis/LoanFactory.abi.js");
const FLFAddress       = require(artpath + "addresses/FundingLockerFactory.address.js");
const FLFABI           = require(artpath + "abis/FundingLockerFactory.abi.js");
const GlobalsAddress   = require(artpath + "addresses/MapleGlobals.address.js");
const GlobalsABI       = require(artpath + "abis/MapleGlobals.abi.js");
const LoanABI          = require(artpath + "abis/Loan.abi.js");

const BulletRepaymentCalc       = require(artpath + "addresses/BulletRepaymentCalc.address.js");
const LateFeeCalc               = require(artpath + "addresses/LateFeeCalc.address.js");
const PremiumCalc               = require(artpath + "addresses/PremiumCalc.address.js");

describe.skip("fundLoan() in Loan.sol", function () {
  const BUNK_ADDRESS = "0x0000000000000000000000000000000000000020";

  let DAI,
    USDC,
    MPL,
    WETH,
    WBTC,
    LoanFactory,
    FundingLockerFactory,
    CollateralLockerFactory,
    Globals,
    accounts;

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

  it("createLoan() with signer(0)", async function () {
    // Grab preIncrementor to get LoanID
    // Note: consider networkVersion=1 interactions w.r.t. async flow
    const preIncrementorValue = await LoanFactory.loansCreated();

    // 5% APR, 90 Day Term, 30 Day Interval, 1000 DAI, 20% Collateral, 7 Day Funding Period
    await LoanFactory.createLoan(
      DAIAddress,
      WBTCAddress,
      [500, 90, 30, BigNumber.from(10).pow(18).mul(1000), 2000, 7],
      [
        AmortizationRepaymentCalc,
        LateFeeCalc,
        PremiumCalc
      ]
    );

    vaultAddress = await LoanFactory.loans(preIncrementorValue);
  });

  it("approve() loanVault to loanAsset with signer(1)", async function () {
    await DAI_EXT_1.approve(vaultAddress, BigNumber.from(10).pow(18).mul(5));

    const allowance = await DAI_EXT_1.allowance(accounts[1], vaultAddress);

    expect(allowance["_hex"]).to.equals(
      BigNumber.from(10).pow(18).mul(5).toHexString()
    );
  });

  it("confirm balance fail fundLoan() with signer(1)", async function () {
    // Unapprove vault and transfer out any DAI from accounts[1]
    await DAI_EXT_1.approve(vaultAddress, 0);
    const transferOutAmount = await DAI.balanceOf(accounts[1]);
    await DAI_EXT_1.transfer(
      BUNK_ADDRESS,
      BigNumber.from(transferOutAmount["_hex"]).toString()
    );

    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(1)
    );

    // Attempt to fund with 100 DAI
    await expect(
      Loan.fundLoan(BigNumber.from(10).pow(18).mul(100), accounts[1])
    ).to.be.revertedWith("ERC20: transfer amount exceeds balance");

    // Mint 100 DAI and attempt to fund
    await DAI.mintSpecial(accounts[1], 100);

    await expect(
      Loan.fundLoan(BigNumber.from(10).pow(18).mul(100), accounts[1])
    ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
  });

  it("fundLoan() with signer(1)", async function () {
    // Mint 100 DAI and attempt to fund
    await DAI.mintSpecial(accounts[1], 100);

    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(1)
    );

    // Approve loanVault for 100 DAI
    await DAI_EXT_1.approve(vaultAddress, BigNumber.from(10).pow(18).mul(100));

    // Attempt to fund with 100 DAI
    await Loan.fundLoan(BigNumber.from(10).pow(18).mul(100), accounts[1]);
  });

  it("confirm loanTokens minted for signer(1)", async function () {
    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(1)
    );

    // Confirm new LoanToken balance is 100(10**18)
    const tokenBalance = await Loan.balanceOf(accounts[1]);

    expect(tokenBalance["_hex"]).to.equals(
      BigNumber.from(10).pow(18).mul(100).toHexString()
    );
  });

  it("confirm fundingLocker has funding", async function () {
    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(1)
    );

    const fundingLockerAddress = await Loan.fundingLocker();

    const fundingLockerBalance = await DAI.balanceOf(fundingLockerAddress);

    expect(fundingLockerBalance["_hex"]).to.equals(
      BigNumber.from(10).pow(18).mul(100).toHexString()
    );
  });

  it("test drawdown calculation endpoint", async function () {
    Loan = new ethers.Contract(
      vaultAddress,
      LoanABI,
      ethers.provider.getSigner(0)
    );

    const drawdownAmount_50USD = await Loan.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(50)
    );

    const drawdownAmount_100USD = await Loan.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(100)
    );
    const drawdownAmount_500USD = await Loan.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(500)
    );

    const drawdownAmount_1000USD = await Loan.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(1000)
    );

    const drawdownAmount_5000USD = await Loan.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(5000)
    );
    const drawdownAmount_10000USD = await Loan.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(10000)
    );

    expect(parseInt(drawdownAmount_50USD["_hex"])).to.not.equals(0);
    expect(parseInt(drawdownAmount_100USD["_hex"])).to.not.equals(0);
    expect(parseInt(drawdownAmount_500USD["_hex"])).to.not.equals(0);
    expect(parseInt(drawdownAmount_1000USD["_hex"])).to.not.equals(0);
    expect(parseInt(drawdownAmount_5000USD["_hex"])).to.not.equals(0);
    expect(parseInt(drawdownAmount_10000USD["_hex"])).to.not.equals(0);
  });

  it("test drawdown functionality", async function () {
    // TODO: Add in this test next.
  });
});
