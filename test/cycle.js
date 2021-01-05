// cycle.js

/*

  This test suite outlines action(s) for the following:

    (P1) Pool delegate initializing a pool
    (P2) Pool delegate minting BPTs .. (assumes USDC / MPL balancer pool already exists with very small amount)
    (P3) Pool delegate staking a pool
    (P4) Pool delegate finalizing a pool
    ..
    (L1) Borrower creating a loan
    ..
    (P5) Provider depositing USDC to a pool
    (P6) Pool delegate funding a loan .. (in slight excess)
    (P7) Liquidity provider withdrawing USDC .. (claimable vs. equity)
    ..
    (L2) Borrower posting collateral and drawing down Loan .. (paying fee and excess)
    (P8) Liquidity pool claiming from loan .. (claiming fee and excess)
    ..
    (L3) Borrower making a single payment .. (paying principal and interest)
    (P9) Liquidity pool claiming from loan .. (claiming principal and interest)
    ..
    (L4) Borrower making a full payment
    ..
    (P10) Pool claiming from loan 
    (P11) Liquidity provider withdrawing USDC

*/

// JS Globals
const { expect, assert } = require("chai");
const { BigNumber }      = require("ethers");
const artpath            = "../../contracts/" + network.name + "/";

// Maple Core Contracts
const GlobalsAddress      = require(artpath + "addresses/MapleGlobals.address");
const GlobalsABI          = require(artpath + "abis/MapleGlobals.abi");
const MPLAddress          = require(artpath + "addresses/MapleToken.address");
const MPLABI              = require(artpath + "abis/MapleToken.abi");
const PoolFactoryAddress  = require(artpath + "addresses/LiquidityPoolFactory.address");
const PoolFactoryABI      = require(artpath + "abis/LiquidityPoolFactory.abi");
const LoanFactoryAddress  = require(artpath + "addresses/LoanVaultFactory.address");
const LoanFactoryABI      = require(artpath + "abis/LoanVaultFactory.abi");

// Maple Misc Contracts
const StakeLockerABI      = require(artpath + "abis/StakeLocker.abi");
const PoolABI             = require(artpath + "abis/LiquidityPool.abi");
const LoanABI             = require(artpath + "abis/LoanVault.abi");
const BulletCalcAddress   = require(artpath + "addresses/BulletRepaymentCalculator.address");
const AmortiCalcAddress   = require(artpath + "addresses/AmortizationRepaymentCalculator.address");
const LateFeeCalcAddress  = require(artpath + "addresses/LateFeeNullCalculator.address");
const PremiumCalcAddress  = require(artpath + "addresses/PremiumFlatCalculator.address");

// External Contracts
const BPoolABI    = require(artpath + "abis/BPool.abi");
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address");
const USDCABI     = require(artpath + "abis/MintableTokenUSDC.abi");
const WETHAddress = require(artpath + "addresses/WETH9.address");
const WETHABI     = require(artpath + "abis/WETH9.abi");
const WBTCAddress = require(artpath + "addresses/WBTC.address");
const WBTCABI     = require(artpath + "abis/WBTC.abi");

describe("Cycle of an entire loan", function () {

  // These are initialized in test suite.
  let Pool, PoolAddress;
  let Loan, LoanAddress;

   // Already existing contracts, assigned in before().
  let Globals;
  let PoolFactory;
  let LoanFactory;
  let BPool;
  let MPL_Delegate, MPL_Staker;
  let USDC_Delegate, USDC_Staker, USDC_Provider;
  let Accounts;

  before(async () => {

    // Core Contracts
    Globals = new ethers.Contract(
      GlobalsAddress,
      GlobalsABI,
      ethers.provider.getSigner(0)
    );
    PoolFactory = new ethers.Contract(
      PoolFactoryAddress,
      PoolFactoryABI,
      ethers.provider.getSigner(0)
    );
    LoanFactory = new ethers.Contract(
      LoanFactoryAddress,
      LoanFactoryABI,
      ethers.provider.getSigner(0)
    );

    // External Contract
    BPool = new ethers.Contract(
      await Globals.mapleBPool(),
      BPoolABI,
      ethers.provider.getSigner(0)
    );

    // MPL
    MPL_Delegate = new ethers.Contract(
      MPLAddress,
      MPLABI,
      ethers.provider.getSigner(0)
    );
    MPL_Staker = new ethers.Contract(
      MPLAddress,
      MPLABI,
      ethers.provider.getSigner(1)
    );

    // USDC
    USDC_Delegate = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(0)
    );
    USDC_Staker = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(1)
    );
    USDC_Provider = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(2)
    );

    Accounts = await ethers.provider.listAccounts();

  });

  it("(P1) Pool delegate initializing a pool", async function () {

    let index = await PoolFactory.liquidityPoolsCreated();

    // Input variables for a form.
    liquidityAsset  = USDCAddress;
    stakeAsset      = await Globals.mapleBPool();
    stakingFee      = 100;  // Basis points (100 = 1%)
    delegateFee     = 150;  // Basis points (150 = 1.5%)
    name            = "Maple Core Pool";
    symbol          = "MCP";

    // Initializing a pool.
    await PoolFactory.createLiquidityPool(
      liquidityAsset,
      stakeAsset,
      stakingFee,
      delegateFee,
      name,
      symbol
    );

    // Assigning contract object to Pool.
    let PoolAddress = await PoolFactory.getLiquidityPool(index);

    Pool = new ethers.Contract(
      PoolAddress,
      PoolABI,
      ethers.provider.getSigner(0)
    );

  });

  it("(P2) Pool delegate minting BPTs", async function () {

    // Assume pool delegate already has 10000 MPL.
    // Mint 10000 USDC for pool delegate.
    USDC_Delegate.mintSpecial(Accounts[0], 5000000);
    
    // Approve the balancer pool for both USDC and MPL.
    USDC_Delegate.approve(
      await Globals.mapleBPool(),
      BigNumber.from(10).pow(6).mul(5000000)
    );
    MPL_Delegate.approve(
      await Globals.mapleBPool(),
      BigNumber.from(10).pow(18).mul(100000)
    );
    
    // Join pool to mint BPTs.
    await BPool.joinPool(
      BigNumber.from(10).pow(17).mul(10), // Set .1 BPTs as expected return.
      [
        BigNumber.from(10).pow(6).mul(5000000), // Caps maximum USDC tokens it can take to 10k
        BigNumber.from(10).pow(18).mul(1000000) // Caps maximum MPL tokens it can take to 10k
      ]
    )

  });

  it("(P3) Pool delegate staking a pool", async function () {

    // Pool delegate approves StakeLocker directly of Pool to take BPTs.
    await BPool.approve(
      await Pool.stakeLockerAddress(),
      BigNumber.from(10).pow(17).mul(10)
    )
    
    // Create StakeLocker object.
    StakeLocker = new ethers.Contract(
      await Pool.stakeLockerAddress(),
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    // Pool delegate stakes to StakeLocker.
    await StakeLocker.stake(BigNumber.from(10).pow(17).mul(10));

  });

  it("(P4) Pool delegate finalizing a pool", async function () {

    // Pool delegate finalizes the pool (enabling deposits).
    await Pool.finalize();
    
    // Confirm pool is finalized.
    let finalized = await Pool.isFinalized();
    expect(finalized);

  });

  it("(L1) Borrower creating a loan", async function () {

    // Default values for creating a loan.
    const assetRequested     = USDCAddress;
    const lateFeeCalculator  = LateFeeCalcAddress;
    const premiumCalculator  = PremiumCalcAddress;

    // Adjustable values for creating a loan.
    const assetCollateral    = WETHAddress; // WETHAddress || WBTCAddress << Use WETHAddress for now
    const interestCalculator = BulletCalcAddress; // AmortiCalcAddress || BulletCalcAddress << Use either

    const aprBips = 500; // 5% APR
    const termDays = 180; // (termDays/paymentIntervalDays) = # of Payments
    const paymentIntervalDays = 30; 
    const minRaise = BigNumber.from(10).pow(6).mul(1000); // 1000 USDC
    const collateralRatioBips = 1000; // 10%
    const fundingPeriodDays = 7;

    const index = await LoanFactory.loanVaultsCreated();

    // Creating a loan.
    await LoanFactory.createLoanVault(
      assetRequested,
      assetCollateral,
      [
        aprBips,
        termDays,
        paymentIntervalDays,
        minRaise,
        collateralRatioBips,
        fundingPeriodDays
      ],
      [
        interestCalculator, 
        lateFeeCalculator, 
        premiumCalculator
      ],
      { gasLimit: 6000000 }
    );

    // Assigning contract object to Loan.
    LoanAddress = await LoanFactory.getLoanVault(index);

    Loan = new ethers.Contract(
      LoanAddress,
      LoanABI,
      ethers.provider.getSigner(0)
    );

  });

  it("(P5) Provider depositing USDC to a pool", async function () {

  });

  it("(P6) Pool delegate funding a loan", async function () {

  });

  it("(P7) Liquidity provider withdrawing USDC", async function () {

  });

  it("(L2) Borrower posting collateral and drawing down loan", async function () {

  });

  it("(P8) Pool claiming from loan", async function () {

  });

  it("(L3) Borrower making a single payment", async function () {

  });

  it("(P9) Pool claiming from loan", async function () {

  });

  it("(L4) Borrower making a full payment", async function () {

  });

  it("(P10) Pool claiming from loan", async function () {

  });

  it("(P11) Liquidity provider withdrawing USDC", async function () {

  });

});