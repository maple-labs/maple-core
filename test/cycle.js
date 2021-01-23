require("dotenv").config();
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
    (P5) Liquidity provider depositing USDC to a pool
    (P6) Pool delegate funding a loan .. (in slight excess)
    (P7) Liquidity provider withdrawing USDC .. (claimable vs. equity)
    ..
    (L2) Borrower posting collateral and drawing down Loan .. (paying fee and excess)
    (P8) Pool claiming from loan .. (claiming fee and excess)
    ..
    (L3) Borrower making a single payment .. (paying principal and interest)
    (P9) Pool claiming from loan .. (claiming principal and interest)
    ..
    (L4) Borrower making a full payment
    ..
    (P10) Pool claiming from loan 
    (P11) Liquidity provider withdrawing USDC

*/

/*

  This test suite triggers the following events:

    Pool:
      - LoanFunded()      >> fundLoan() 
      - BalanceUpdated()  >> claim(), deposit(), withdraw(), fundLoan()
      - Claim()           >> claim()

    PoolFactory:
      - PoolCreated()     >> createPool()
    
    Loan:
      - LoanFunded()      >> fundLoan()
      - BalanceUpdated()  >> fundLoan(), drawdown(), makePayment(), makeFullPayment()

    LoanFactory:
      - LoanCreated() >> createLoan()

    StakeLocker:
      - BalanceUpdated()  >> stake(), unstake()
      - Stake()           >> stake()
      - Unstake()         >> unstake()

*/

// JS Globals
const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const artpath = `../../contracts/localhost/`;

// Maple Core Contracts
const GlobalsAddress = require(artpath + "addresses/MapleGlobals.address");
const GlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
const MPLAddress = require(artpath + "addresses/MapleToken.address");
const MPLABI = require(artpath + "abis/MapleToken.abi.js");
const PoolFactoryAddress = require(artpath + "addresses/PoolFactory.address");
const PoolFactoryABI = require(artpath + "abis/PoolFactory.abi.js");
const LoanFactoryAddress = require(artpath + "addresses/LoanFactory.address");
const LoanFactoryABI = require(artpath + "abis/LoanFactory.abi.js");

// DL = Debt Locker, FL = Funding Locker, CL = Collateral Locker, SL = StakeLocker, LL = LiquidityLocker
const DLFactoryAddress = require(artpath +
  "addresses/DebtLockerFactory.address");
const FLFactoryAddress = require(artpath +
  "addresses/FundingLockerFactory.address");
const CLFactoryAddress = require(artpath +
  "addresses/CollateralLockerFactory.address");
const SLFactoryAddress = require(artpath +
  "addresses/StakeLockerFactory.address");
const LLFactoryAddress = require(artpath +
  "addresses/LiquidityLockerFactory.address");

// Maple Misc Contracts
const StakeLockerABI = require(artpath + "abis/StakeLocker.abi.js");
const PoolABI = require(artpath + "abis/Pool.abi.js");
const LoanABI = require(artpath + "abis/Loan.abi.js");
const BulletCalcAddress = require(artpath +
  "addresses/BulletRepaymentCalc.address");
const LateFeeCalcAddress = require(artpath + "addresses/LateFeeCalc.address");
const PremiumCalcAddress = require(artpath + "addresses/PremiumCalc.address");

const BCreatorABI = require(artpath + "abis/BCreator.abi.js");
const BCreatorAddress = require(artpath + "addresses/BCreator.address.js");

// External Contracts
const BPoolABI = require(artpath + "abis/BPool.abi.js");
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address");
const USDCABI = require(artpath + "abis/MintableTokenUSDC.abi.js");
const WETHAddress = require(artpath + "addresses/WETH9.address");
const WETHABI = require(artpath + "abis/WETH9.abi.js");
const WBTCAddress = require(artpath + "addresses/WBTC.address");
const WBTCABI = require(artpath + "abis/WBTC.abi.js");

describe("Cycle of an entire loan", function () {
  // These are initialized in test suite.
  let Pool_PoolDelegate, Pool_LiquidityProvider, PoolAddress;
  let Loan, LoanAddress;

  // Already existing contracts, assigned in before().
  let Globals;
  let PoolFactory;
  let LoanFactory;
  let BPool;
  let MPL_Delegate, MPL_Staker;
  let USDC_Delegate, USDC_Staker, USDC_Provider, USDC_Borrower;
  let WETH_Borrower, WBTC_Borrower;
  let Accounts;
  let MapleBPoolAddress;

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

    // Fetch the official Maple balancer pool address.
    BCreator = new ethers.Contract(
      BCreatorAddress,
      BCreatorABI,
      ethers.provider.getSigner(0)
    );
    MapleBPoolAddress = await BCreator.getBPoolAddress(0);

    // External Contract
    BPool = new ethers.Contract(
      MapleBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    );

    // MPL
    MPL_PoolDelegate = new ethers.Contract(
      MPLAddress,
      MPLABI,
      ethers.provider.getSigner(0)
    );
    MPL_Staker = new ethers.Contract(
      MPLAddress,
      MPLABI,
      ethers.provider.getSigner(2)
    );

    // USDC
    USDC_PoolDelegate = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(0)
    );
    USDC_LiquidityProvider = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(1)
    );
    USDC_Staker = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(2)
    );
    USDC_Borrower = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(0) // Same as USDC_PoolDelegate
    );

    // WETH / WBTC
    WETH_Borrower = new ethers.Contract(
      WETHAddress,
      WETHABI,
      ethers.provider.getSigner(0)
    );
    WBTC_Borrower = new ethers.Contract(
      WBTCAddress,
      WBTCABI,
      ethers.provider.getSigner(0)
    );

    // Accounts
    Accounts = await ethers.provider.listAccounts();
  });

  it("(P1) Pool delegate initializing a pool", async function () {
    let index = await PoolFactory.poolsCreated();

    // Input variables for a form.
    liquidityAsset = USDCAddress;
    stakeAsset = MapleBPoolAddress;
    slFactory = SLFactoryAddress;
    llFactory = LLFactoryAddress;
    stakingFee = 100; // Basis points (100 = 1%)
    delegateFee = 150; // Basis points (150 = 1.5%)
    liquidityCap = BigNumber.from(10).pow(6).mul(100000000);

    // Initializing a pool.
    await PoolFactory.createPool(
      liquidityAsset,
      stakeAsset,
      slFactory,
      llFactory,
      stakingFee,
      delegateFee,
      liquidityCap
    );

    // Assigning contract object to Pool.
    PoolAddress = await PoolFactory.pools(parseInt(index["_hex"]));

    while (PoolAddress == "0x0000000000000000000000000000000000000000") {
      PoolAddress = await PoolFactory.pools(parseInt(index["_hex"]));
    }

    Pool_PoolDelegate = new ethers.Contract(
      PoolAddress,
      PoolABI,
      ethers.provider.getSigner(0)
    );

    Pool_LiquidityProvider = new ethers.Contract(
      PoolAddress,
      PoolABI,
      ethers.provider.getSigner(1)
    );
  });

  it("(P2) Pool delegate minting BPTs", async function () {
    // Assume pool delegate already has 10000 MPL.
    // Mint 10000 USDC for pool delegate.
    await USDC_PoolDelegate.mintSpecial(Accounts[0], 5000000);

    // Approve the balancer pool for both USDC and MPL.
    await USDC_PoolDelegate.approve(
      MapleBPoolAddress,
      BigNumber.from(10).pow(6).mul(5000000)
    );
    await MPL_PoolDelegate.approve(
      MapleBPoolAddress,
      BigNumber.from(10).pow(18).mul(100000)
    );

    // Join pool to mint BPTs.
    await BPool.joinPool(
      BigNumber.from(10).pow(17).mul(10), // Set .1 BPTs as expected return.
      [
        BigNumber.from(10).pow(6).mul(5000000), // Caps maximum USDC tokens it can take to 10k
        BigNumber.from(10).pow(18).mul(1000000), // Caps maximum MPL tokens it can take to 10k
      ]
    );
  });

  it("(P3) Pool delegate staking a pool", async function () {
    // Pool delegate approves StakeLocker directly of Pool to take BPTs.
    await BPool.approve(
      await Pool_PoolDelegate.stakeLocker(),
      BigNumber.from(10).pow(17).mul(10)
    );

    // Create StakeLocker object.
    StakeLocker = new ethers.Contract(
      await Pool_PoolDelegate.stakeLocker(),
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    // Pool delegate stakes to StakeLocker.
    await StakeLocker.stake(BigNumber.from(10).pow(17).mul(10));
  });

  it("(P4) Pool delegate finalizing a pool", async function () {
    // Pool delegate finalizes the pool (enabling deposits).
    await Pool_PoolDelegate.finalize();

    // Confirm pool is finalized.
    let finalized = await Pool_PoolDelegate.isFinalized();
    expect(finalized);
  });

  it("(L1) Borrower creating a loan", async function () {
    // Default values for creating a loan.
    const loanAsset = USDCAddress;
    const lateFeeCalc = LateFeeCalcAddress;
    const premiumCalc = PremiumCalcAddress;
    const flFactory = FLFactoryAddress;
    const clFactory = CLFactoryAddress;

    // Adjustable values for creating a loan.
    const collateralAsset = WETHAddress; // WETHAddress || WBTCAddress << Use WETHAddress for now
    const interestCalc = BulletCalcAddress;

    const apr = 500; // 5% APR
    const termDays = 180; // (termDays/paymentIntervalDays) = # of Payments
    const paymentIntervalDays = 30;
    const minRaise = BigNumber.from(10).pow(6).mul(1000); // 1000 USDC
    const collateralRatioBips = 1000; // 10%
    const fundingPeriodDays = 7;

    const index = await LoanFactory.loansCreated();

    // Creating a loan.
    await LoanFactory.createLoan(
      loanAsset,
      collateralAsset,
      flFactory,
      clFactory,
      [
        apr,
        termDays,
        paymentIntervalDays,
        minRaise,
        collateralRatioBips,
        fundingPeriodDays,
      ],
      [interestCalc, lateFeeCalc, premiumCalc],
      { gasLimit: 6000000 }
    );

    if (parseInt(index["_hex"]) == 0 && process.env.NETWORK !== 'localhost') {
      // Creating a 2nd loan.
      await LoanFactory.createLoan(
        loanAsset,
        collateralAsset,
        flFactory,
        clFactory,
        [
          apr,
          termDays,
          paymentIntervalDays,
          minRaise,
          collateralRatioBips,
          fundingPeriodDays,
        ],
        [interestCalc, lateFeeCalc, premiumCalc],
        { gasLimit: 6000000 }
      );
    }

    // Assigning contract object to Loan.
    LoanAddress = await LoanFactory.loans(parseInt(index["_hex"]));

    while (LoanAddress == "0x0000000000000000000000000000000000000000") {
      LoanAddress = await LoanFactory.loans(parseInt(index["_hex"]));
    }

    Loan = new ethers.Contract(
      LoanAddress,
      LoanABI,
      ethers.provider.getSigner(0)
    );
  });

  it("(P5) Provider depositing USDC to a pool", async function () {
    // Approve the pool for deposit.
    await USDC_LiquidityProvider.approve(
      PoolAddress,
      BigNumber.from(10).pow(6).mul(2500) // Deposit = 2500 USDC
    );

    // Deposit to the pool.
    await Pool_LiquidityProvider.deposit(BigNumber.from(10).pow(6).mul(2500));
  });

  it("(P6) Pool delegate funding a loan", async function () {

    // Pool delegate funding the loan.
    await Pool_PoolDelegate.fundLoan(
      LoanAddress,
      DLFactoryAddress,
      BigNumber.from(10).pow(6).mul(1500)
    );
  });

  it("(P7) Liquidity provider withdrawing USDC", async function () {
    // Withdraw USDC from the pool.
    await Pool_LiquidityProvider.withdraw(
      BigNumber.from(10).pow(6).mul(500) // "Burning" 500 * 10 ** 18 pool tokens corresponds to 500 USDC.
    );
  });

  it("(L2) Borrower posting collateral and drawing down loan", async function () {
    // Fetch collateral required when drawing down 1000 USDC (1500 USDC was funded)
    const collateralRequired = await Loan.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(6).mul(1000)
    );

    // Approve Loan for collateral required. Use "WBTC" object instead if WBTC is collateral.
    await ethers.provider.getSigner(0).sendTransaction({to: WETHAddress, value: collateralRequired});
    let y = await WETH_Borrower.balanceOf(Accounts[0]);
    await WETH_Borrower.approve(LoanAddress, collateralRequired);

    // Drawdown.
    await Loan.drawdown(BigNumber.from(10).pow(6).mul(1000));
  });

  it("(P8) Pool claiming from loan", async function () {
    // Pool claims and distributes syrup.
    await Pool_PoolDelegate.claim(LoanAddress, DLFactoryAddress);
  });

  it("(L3) Borrower making a single payment", async function () {
    // Fetch next payment amount.
    const paymentInfo = await Loan.getNextPayment();

    // Approve loan for payment.
    await USDC_Borrower.approve(LoanAddress, paymentInfo[0]);

    await USDC_Borrower.mintSpecial(Accounts[0], 500000000000);

    const USDC_Balance = await USDC_Borrower.balanceOf(Accounts[0]);
    // console.log(parseInt(USDC_Balance["_hex"]))

    // Make payment.
    await Loan.makePayment();
  });

  it("(P9) Pool claiming from loan", async function () {
    // Pool claims and distributes syrup.
    await Pool_PoolDelegate.claim(LoanAddress, DLFactoryAddress);
  });

  it("(L4) Borrower making a full payment", async function () {
    // Fetch full payment amount.
    const paymentInfo = await Loan.getFullPayment();

    // Approve loan for payment.
    await USDC_Borrower.approve(LoanAddress, paymentInfo[0]);

    // Make payment.
    await Loan.makeFullPayment();
  });

  it("(P10) Pool claiming from loan", async function () {
    // Pool claims and distributes syrup.
    await Pool_PoolDelegate.claim(LoanAddress, DLFactoryAddress);
  });

  xit("(P11) Liquidity provider withdrawing USDC", async function () {
    // Note: Keep this test commented out, there is critical failure
    //       in the withdraw() function currently.

    // Withdraw USDC from the pool.
    await Pool_LiquidityProvider.withdraw(
      BigNumber.from(10).pow(18).mul(2000) // "Burning" 18 decimals worth of shares (maps to 6 decimals worth of USDC)
    );
  });
});
