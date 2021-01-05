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

// Core Contracts
const GlobalsAddress      = require(artpath + "addresses/MapleGlobals.address");
const GlobalsABI          = require(artpath + "abis/MapleGlobals.abi");
const MPLAddress          = require(artpath + "addresses/MapleToken.address");
const MPLABI              = require(artpath + "abis/MapleToken.abi");
const PoolFactoryAddress  = require(artpath + "addresses/LiquidityPoolFactory.address");
const PoolFactoryABI      = require(artpath + "abis/LiquidityPoolFactory.abi");
const VaultFactoryAddress = require(artpath + "addresses/LoanVaultFactory.address");
const VaultFactoryABI     = require(artpath + "abis/LoanVaultFactory.abi");
const StakeLockerABI      = require(artpath + "abis/StakeLocker.abi");
const PoolABI             = require(artpath + "abis/LiquidityPool.abi");

// External Contracts
const BPoolABI    = require(artpath + "abis/BPool.abi");
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address");
const USDCABI     = require(artpath + "abis/MintableTokenUSDC.abi");

describe("Cycle of an entire loan", function () {

  // These are initialized in test suite.
  let Pool, PoolAddress;
  let Loan, LoanAddress;

   // Already existing contracts, assigned in before().
  let Globals;
  let PoolFactory;
  let VaultFactory;
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
    VaultFactory = new ethers.Contract(
      VaultFactoryAddress,
      VaultFactoryABI,
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
    USDC_Delegate.mintSpecial(Accounts[0], 10000);
    
    // Approve the balancer pool for both USDC and MPL.
    USDC_Delegate.approve(
      await Globals.mapleBPool(),
      BigNumber.from(10).pow(6).mul(10000)
    );
    MPL_Delegate.approve(
      await Globals.mapleBPool(),
      BigNumber.from(10).pow(18).mul(10000)
    );

    const preBPTs = await BPool.balanceOf(Accounts[0]);
    
    // Join pool to mint BPTs.
    await BPool.joinPool(
      BigNumber.from(10).pow(16).mul(1), // Set .01 BPTs as expected return.
      [
        BigNumber.from(10).pow(6).mul(10000), // Caps maximum USDC tokens it can take to 10k
        BigNumber.from(10).pow(18).mul(10000) // Caps maximum MPL tokens it can take to 10k
      ]
    )
    
    const postBPTs = await BPool.balanceOf(Accounts[0]);

    console.log(parseInt(preBPTs["_hex"]))
    console.log(parseInt(postBPTs["_hex"]))

  });

  it("(P3) Pool delegate staking a pool", async function () {

    // Pool delegate approves StakeLocker directly of Pool to take BPTs.
    await BPool.approve(
      await Pool.stakeLockerAddress(),
      BigNumber.from(10).pow(16).mul(1)
    )
    
    // Create StakeLocker object.
    StakeLocker = new ethers.Contract(
      await Pool.stakeLockerAddress(),
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    // Pool delegate stakes to StakeLocker.
    await StakeLocker.stake(BigNumber.from(10).pow(16).mul(1));

  });

  it("(P4) Pool delegate finalizing a pool", async function () {

    await Pool.finalize();
    
    let stakeRequired = await Globals.stakeAmountRequired();
    let finalized = await Pool.isFinalized();

    console.log(parseInt(stakeRequired["_hex"]));
    expect(finalized);

  });

  it("(L1) Borrower creating a loan", async function () {

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