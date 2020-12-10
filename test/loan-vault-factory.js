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
const CLFAddress = require(artpath + "addresses/CollateralLockerFactory.address.js");
const CLFABI = require(artpath + "abis/CollateralLockerFactory.abi.js");
const LALFAddress = require(artpath + "addresses/LiquidityLockerFactory.address.js");
const LALFABI = require(artpath + "abis/LiquidityLockerFactory.abi.js");
const GlobalsAddress = require(artpath + "addresses/MapleGlobals.address.js");
const GlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
const LoanVaultABI = require(artpath + "abis/LoanVault.abi.js");

describe("LoanVaultFactory.sol / LoanVault.sol", function () {
  const BUNK_ADDRESS = "0x0000000000000000000000000000000000000000";
  const BUNK_ADDRESS_AMORTIZATION =
    "0x0000000000000000000000000000000000000001";
  const BUNK_ADDRESS_BULLET = "0x0000000000000000000000000000000000000002";

  let DAI,
    USDC,
    MPL,
    WETH,
    WBTC,
    LoanVaultFactory,
    FundingLockerFactory,
    CollateralLockerFactory,
    Globals;

  before(async () => {
    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));
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
    CollateralLockerFactory = new ethers.Contract(
      CLFAddress,
      CLFABI,
      ethers.provider.getSigner(0)
    );
    LiquidLockerFactory = new ethers.Contract(
      LALFAddress,
      LALFABI,
      ethers.provider.getSigner(0)
    );
    Globals = new ethers.Contract(
      GlobalsAddress,
      GlobalsABI,
      ethers.provider.getSigner(0)
    );
  });

  let vaultAddress;

  it("test invalid instantiations from loanVault from factory", async function () {
    await expect(
      LoanVaultFactory.createLoanVault(
        DAIAddress,
        WETHAddress,
        [5000, 0, 0, 0, 0, 0],
        ethers.utils.formatBytes32String("BALLET")
      )
    ).to.be.revertedWith(
      "LoanVaultFactory::createLoanVault:ERR_NULL_INTEREST_STRUCTURE_CALC"
    );

    await expect(
      LoanVaultFactory.createLoanVault(
        DAIAddress,
        WETHAddress,
        [5000, 0, 0, 0, 0, 0],
        ethers.utils.formatBytes32String("BULLET")
      )
    ).to.be.revertedWith(
      "LoanVault::constructor:ERR_PAYMENT_INTERVAL_DAYS_EQUALS_ZERO"
    );

    await expect(
      LoanVaultFactory.createLoanVault(
        BUNK_ADDRESS,
        WETHAddress,
        [5000, 0, 0, 0, 0, 0],
        ethers.utils.formatBytes32String("BULLET")
      )
    ).to.be.revertedWith(
      "LoanVault::constructor:ERR_INVALID_FUNDS_TOKEN_ADDRESS"
    );

    await expect(
      LoanVaultFactory.createLoanVault(
        DAIAddress,
        BUNK_ADDRESS,
        [5000, 0, 0, 0, 0, 0],
        ethers.utils.formatBytes32String("AMORTIZATION")
      )
    ).to.be.revertedWith(
      "LoanVaultFactory::createLoanVault:ERR_NULL_ASSET_COLLATERAL"
    );

    await expect(
      LoanVaultFactory.createLoanVault(
        DAIAddress,
        WETHAddress,
        [5000, 0, 0, 0, 0, 0],
        ethers.utils.formatBytes32String("BULLET")
      )
    ).to.be.revertedWith(
      "LoanVault::constructor:ERR_PAYMENT_INTERVAL_DAYS_EQUALS_ZERO"
    );

    await expect(
      LoanVaultFactory.createLoanVault(
        DAIAddress,
        WETHAddress,
        [5000, 1, 0, 0, 0, 0],
        ethers.utils.formatBytes32String("AMORTIZATION")
      )
    ).to.be.revertedWith(
      "LoanVault::constructor:ERR_PAYMENT_INTERVAL_DAYS_EQUALS_ZERO"
    );

    await expect(
      LoanVaultFactory.createLoanVault(
        DAIAddress,
        WETHAddress,
        [5000, 30, 29, 1000000000000, 0, 0],
        ethers.utils.formatBytes32String("BULLET")
      )
    ).to.be.revertedWith(
      "LoanVault::constructor:ERR_INVALID_TERM_AND_PAYMENT_INTERVAL_DIVISION"
    );

    await expect(
      LoanVaultFactory.createLoanVault(
        DAIAddress,
        WETHAddress,
        [5000, 30, 30, 0, 0, 0],
        ethers.utils.formatBytes32String("BULLET")
      )
    ).to.be.revertedWith("LoanVault::constructor:ERR_MIN_RAISE_EQUALS_ZERO");

    await expect(
      LoanVaultFactory.createLoanVault(
        DAIAddress,
        WETHAddress,
        [5000, 90, 30, 1000000000000, 0, 0],
        ethers.utils.formatBytes32String("AMORTIZATION")
      )
    ).to.be.revertedWith(
      "LoanVault::constructor:ERR_FUNDING_PERIOD_EQUALS_ZERO"
    );
  });

  it("instantiate loanVault from factory", async function () {
    // Confirm incrementor pre/post-checks.
    const preIncrementorValue = await LoanVaultFactory.loanVaultsCreated();

    await LoanVaultFactory.createLoanVault(
      DAIAddress,
      WETHAddress,
      [5000, 90, 30, 1000000000000, 0, 7],
      ethers.utils.formatBytes32String("AMORTIZATION")
    );

    const postIncrementorValue = await LoanVaultFactory.loanVaultsCreated();

    expect(parseInt(postIncrementorValue["_hex"]) - 1).to.equals(
      parseInt(preIncrementorValue["_hex"])
    );

    // Fetch address of the LoanVault, confirm the address passes isLoanVault() identifcation check.
    const loanVaultAddress = await LoanVaultFactory.getLoanVault(
      preIncrementorValue
    );
    vaultAddress = loanVaultAddress;

    const isLoanVault = await LoanVaultFactory.isLoanVault(loanVaultAddress);

    expect(isLoanVault);

    let LoanVaultContract = new ethers.Contract(
      loanVaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const fundingLockerAddress = await LoanVaultContract.fundingLocker();
    const owner = await FundingLockerFactory.getOwner(fundingLockerAddress);

    expect(vaultAddress).to.equals(owner);
  });

  it("confirm loanVault borrower, other state vars, and specifications", async function () {
    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const accounts = await ethers.provider.listAccounts();
    const borrower = await LoanVault.borrower();
    expect(borrower).to.equals(accounts[0]);
    /**
      await LoanVaultFactory.createLoanVault(
        DAIAddress,
        WETHAddress,
        [5000, 90, 30, 1000000000000, 0, 7], 
        ethers.utils.formatBytes32String('AMORTIZATION')
      )
    */

    // Ensure that state variables of new LoanVault has proper values.
    const APR_BIPS = await LoanVault.aprBips();
    const NUMBER_OF_PAYMENTS = await LoanVault.numberOfPayments();
    const PAYMENT_INTERVAL_SECONDS = await LoanVault.paymentIntervalSeconds();
    const MIN_RAISE = await LoanVault.minRaise();
    const COLLATERAL_BIPS_RATIO = await LoanVault.collateralBipsRatio();
    const FUNDING_PERIOD_SECONDS = await LoanVault.fundingPeriodSeconds();
    const REPAYMENT_CALCULATOR = await LoanVault.repaymentCalculator();
    const PREMIUM_CALCULATOR = await LoanVault.premiumCalculator();
    const LOAN_STATE = await LoanVault.loanState();

    expect(parseInt(APR_BIPS["_hex"])).to.equals(5000);
    expect(parseInt(NUMBER_OF_PAYMENTS["_hex"])).to.equals(3);
    expect(parseInt(PAYMENT_INTERVAL_SECONDS["_hex"])).to.equals(2592000);
    expect(parseInt(MIN_RAISE["_hex"])).to.equals(1000000000000);
    expect(parseInt(COLLATERAL_BIPS_RATIO["_hex"])).to.equals(0);
    expect(parseInt(FUNDING_PERIOD_SECONDS["_hex"])).to.equals(604800);
    expect(REPAYMENT_CALCULATOR).to.equals(BUNK_ADDRESS_AMORTIZATION);
    expect(LOAN_STATE).to.equals(0);

    // Ensure that the LoanVault was issued and assigned a valid FundingLocker.
    const FUNDING_LOCKER = await LoanVault.fundingLocker();
    const IS_VALID_FUNDING_LOCKER = await FundingLockerFactory.verifyLocker(
      FUNDING_LOCKER
    );
    const FUNDING_LOCKER_OWNER = await FundingLockerFactory.getOwner(
      FUNDING_LOCKER
    );

    expect(FUNDING_LOCKER).to.not.equals(BUNK_ADDRESS);
    expect(IS_VALID_FUNDING_LOCKER);
    expect(FUNDING_LOCKER_OWNER).to.equals(vaultAddress);
  });

  it("adjust loanVaultFactory state vars - fundingLockerFactory / collateralLockerFactory", async function () {
    // Instantiate LVF object via getSigner(1) [non-governor].
    LoanVaultFactory_EXTERNAL_USER = new ethers.Contract(
      LVFactoryAddress,
      LVFactoryABI,
      ethers.provider.getSigner(1)
    );

    // Perform isGovernor modifier checks.
    await expect(
      LoanVaultFactory_EXTERNAL_USER.setFundingLockerFactory(BUNK_ADDRESS)
    ).to.be.revertedWith("LoanVaultFactory::ERR_MSG_SENDER_NOT_GOVERNOR");

    await expect(
      LoanVaultFactory_EXTERNAL_USER.setFundingLockerFactory(BUNK_ADDRESS)
    ).to.be.revertedWith("LoanVaultFactory::ERR_MSG_SENDER_NOT_GOVERNOR");

    // Save current factory addresses, update state vars to new addresses via Governor.
    const currentFundingLockerFactory = await LoanVaultFactory.fundingLockerFactory();
    const currentCollateralLockerFactory = await LoanVaultFactory.collateralLockerFactory();
    const BUNK_ADDRESS_FUNDING_LOCKER_FACTORY =
      "0x0000000000000000000000000000000000000005";
    const BUNK_ADDRESS_COLLATERAL_LOCKER_FACTORY =
      "0x0000000000000000000000000000000000000006";

    await LoanVaultFactory.setFundingLockerFactory(
      BUNK_ADDRESS_FUNDING_LOCKER_FACTORY
    );
    await LoanVaultFactory.setCollateralLockerFactory(
      BUNK_ADDRESS_COLLATERAL_LOCKER_FACTORY
    );
    const newFundingLockerFactory = await LoanVaultFactory.fundingLockerFactory();
    const newCollateralLockerFactory = await LoanVaultFactory.collateralLockerFactory();

    expect(newFundingLockerFactory).to.equals(
      BUNK_ADDRESS_FUNDING_LOCKER_FACTORY
    );
    expect(newCollateralLockerFactory).to.equals(
      BUNK_ADDRESS_COLLATERAL_LOCKER_FACTORY
    );

    // Revert to initial factory addresses.
    await LoanVaultFactory.setFundingLockerFactory(currentFundingLockerFactory);
    await LoanVaultFactory.setCollateralLockerFactory(
      currentCollateralLockerFactory
    );
    const revertedFundingLockerFactory = await LoanVaultFactory.fundingLockerFactory();
    const revertedCollateralLockerFactory = await LoanVaultFactory.collateralLockerFactory();

    expect(revertedFundingLockerFactory).to.equals(currentFundingLockerFactory);
    expect(revertedCollateralLockerFactory).to.equals(
      currentCollateralLockerFactory
    );
  });
  it("Check symbol and name UUID match in symbol and name", async function () {
    const loanVaultAddress1 = await LoanVaultFactory.getLoanVault(0);
    const loanVaultAddress2 = await LoanVaultFactory.getLoanVault(1);
    LoanVault1 = new ethers.Contract(
      loanVaultAddress1,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );
    LoanVault2 = new ethers.Contract(
      loanVaultAddress2,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const symbol1 = await LoanVault1.symbol();
    const desc1 = await LoanVault1.name();
    const symbol2 = await LoanVault2.symbol();
    const desc2 = await LoanVault2.name();
    expect(symbol1.length).to.equal(10);
    expect(symbol1.length).to.equal(symbol2.length);
    expect(desc1.length).to.equal(desc2.length);
    expect(desc1.search(symbol1.slice(2, 12)) > 0).to.equal(true);
    expect(symbol1).to.not.equal(symbol2);
  });
});
