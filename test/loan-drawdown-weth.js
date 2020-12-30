
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

const AmortizationRepaymentCalculator = require(artpath + "addresses/AmortizationRepaymentCalculator.address.js");
const BulletRepaymentCalculator = require(artpath + "addresses/BulletRepaymentCalculator.address.js");
const LateFeeNullCalculator = require(artpath + "addresses/LateFeeNullCalculator.address.js");
const PremiumFlatCalculator = require(artpath + "addresses/PremiumFlatCalculator.address.js");



describe("create 1000 USDC loan, fund 500 USDC, drawdown 50% wETH collateralized loan", function () {

  const BUNK_ADDRESS = "0x0000000000000000000000000000000000000020";

  let DAI,USDC,MPL,WETH,WBTC;
  let LoanVaultFactory,FundingLockerFactory,CollateralLockerFactory;
  let Globals,accounts;

  before(async () => {
    accounts = await ethers.provider.listAccounts();
    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));
    USDC_EXT_1 = new ethers.Contract(USDCAddress, USDCABI, ethers.provider.getSigner(1));
    USDC_EXT_2 = new ethers.Contract(USDCAddress, USDCABI, ethers.provider.getSigner(2));
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

  let vaultAddress;

  it("createLoanVault(), requesting 1000 USDC", async function () {

    
    // Grab preIncrementor to get LoanVaultID
    // Note: consider networkVersion=1 interactions w.r.t. async flow
    const preIncrementorValue = await LoanVaultFactory.loanVaultsCreated();

    // 5% APR, 90 Day Term, 30 Day Interval, 1000 USDC, 20% Collateral, 7 Day Funding Period
    await LoanVaultFactory.createLoanVault(
      USDCAddress,
      WETHAddress,
      [500, 90, 30, BigNumber.from(10).pow(6).mul(1000), 5000, 7], 
      [
	BulletRepaymentCalculator,
	LateFeeNullCalculator,
	PremiumFlatCalculator
      ]
    )
    
    vaultAddress = await LoanVaultFactory.getLoanVault(preIncrementorValue);

  });

  it("fund loan for 500 USDC", async function () {

    await USDC_EXT_1.mintSpecial(accounts[1], 500)
    await USDC_EXT_1.approve(vaultAddress,BigNumber.from(10).pow(6).mul(500))

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(1)
    );

    // Fund loan with 500 USDC
    await LoanVault.fundLoan(
      BigNumber.from(10).pow(6).mul(500),
      accounts[1]
    )

  });

  it("view collateral amount required", async function () {

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const drawdownAmount_500USDC = await LoanVault.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(500)
    )

    // console.log(parseInt(drawdownAmount_500USDC["_hex"]))

  });

  it("drawdown 500 USDC and commence loan (failure)", async function () {

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const drawdownAmount_500USDC = await LoanVault.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(500)
    )

    await WETH.approve(
      vaultAddress,
      BigNumber.from(10).pow(18).mul(Math.round(parseInt(drawdownAmount_500USDC["_hex"]) / 10**16)).mul(100)
    )
    
    await expect(
      LoanVault.drawdown(BigNumber.from(10).pow(6).mul(1000))
    ).to.be.revertedWith("LoanVault::endFunding::ERR_DRAWDOWN_AMOUNT_ABOVE_FUNDING_LOCKER_BALANCE");

    await expect(
      LoanVault.drawdown(BigNumber.from(10).pow(6).mul(500))
    ).to.be.revertedWith("LoanVault::endFunding::ERR_DRAWDOWN_AMOUNT_BELOW_MIN_RAISE");
    
  });

  it("fund 1000 more USDC", async function () {

    await USDC_EXT_1.mintSpecial(accounts[1], 1000)
    await USDC_EXT_1.approve(vaultAddress,BigNumber.from(10).pow(6).mul(1000))

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(1)
    );

    // Fund loan with 1000 USDC
    await LoanVault.fundLoan(
      BigNumber.from(10).pow(6).mul(1000),
      accounts[1]
    )
    
  });

  it("drawdown 1000 USDC and commence loan", async function () {

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const drawdownAmount_1000USDC = await LoanVault.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(18).mul(1000)
    )

    await WETH.approve(
      vaultAddress,
      BigNumber.from(10).pow(18).mul(Math.round(parseInt(drawdownAmount_1000USDC["_hex"]) / 10**16)).mul(100)
    )
    
    
    const PRE_LOCKER_BALANCE = await LoanVault.getFundingLockerBalance();
    const PRE_BORROWER_BALANCE = await USDC.balanceOf(accounts[0]);
    const PRE_LOANVAULT_BALANCE = await USDC.balanceOf(vaultAddress);

    await LoanVault.drawdown(BigNumber.from(10).pow(6).mul(1000));
    
    const POST_LOCKER_BALANCE = await LoanVault.getFundingLockerBalance();
    const POST_BORROWER_BALANCE = await USDC.balanceOf(accounts[0]);
    const POST_LOANVAULT_BALANCE = await USDC.balanceOf(vaultAddress);

    // Confirm the state of various contracts.

    const LoanVaultState = await LoanVault.loanState();

    expect(LoanVaultState).to.equals(1);

    expect(
      parseInt(POST_BORROWER_BALANCE["_hex"]) - parseInt(PRE_BORROWER_BALANCE["_hex"])
    ).to.equals(parseInt(BigNumber.from(10).pow(6).mul(1000)["_hex"]));

    expect(
      parseInt(PRE_LOCKER_BALANCE["_hex"]) - parseInt(POST_LOCKER_BALANCE["_hex"])
    ).to.equals(parseInt(BigNumber.from(10).pow(6).mul(1500)["_hex"]));

    expect(
      parseInt(POST_LOANVAULT_BALANCE["_hex"]) - parseInt(PRE_LOANVAULT_BALANCE["_hex"])
    ).to.equals(parseInt(BigNumber.from(10).pow(6).mul(500)["_hex"]));
    
  });

});
