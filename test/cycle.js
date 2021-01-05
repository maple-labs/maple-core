// cycle.js

/*

  This test suite outlines action(s) for the following:

    (P1) Pool manager initializing a pool
    (P2) Pool manager minting BPTs .. (assumes USDC / MPL balancer pool already exists with very small amount)
    (P3) Pool manager staking a pool
    (P4) Pool manager finalizing a pool
    ..
    (L1) Borrower creating a loan
    ..
    (P5) Provider depositing USDC to a pool
    (P6) Delegate funding a loan .. (in slight excess)
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
    (P10) Liquidity pool claiming from loan 
    (P11) Liquidity provider withdrawing USDC from pool

*/


// JS Globals
const { expect, assert } = require("chai");
const artpath            = "../../contracts/" + network.name + "/";

// Maple
const GlobalsAddress      = require(artpath + "addresses/MapleGlobals.address");
const GlobalsABI          = require(artpath + "abis/MapleGlobals.abi");
const PoolFactoryAddress  = require(artpath + "addresses/LiquidityPoolFactory.address");
const PoolFactoryABI      = require(artpath + "abis/LiquidityPoolFactory.abi");
const VaultFactoryAddress = require(artpath + "addresses/LoanVaultFactory.address");
const VaultFactoryABI     = require(artpath + "abis/LoanVaultFactory.abi");

// External
const BPoolABI    = require(artpath + "abis/BPool.abi");
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address");
const USDCABI     = require(artpath + "abis/MintableTokenUSDC.abi");

describe("Full Cycle of Loan", function () {

  // Dynamic contracts, assigned values throughout test suite.
  let Pool_DAI;
  let Loan_DAI; // Loan contract that borrower creates and makes payments to
  let USDC; // The asset that is used for this loan.
  let DAI;  // Another asset used in PoolDAI

  // Static contracts, set below in before() function.
  let Globals, PoolFactory, VaultFactory, BPool;

  before(async () => {
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
    BPool = new ethers.Contract(
      await Globals.mapleBPool(),
      BPoolABI,
      ethers.provider.getSigner(0)
    );
  });

  it("(P1) Pool manager initializing a pool", async function () {

    const isFinalized = await BPool.isFinalized();

    console.log(isFinalized);

  });

  it("(P2) Pool manager minting BPTs", async function () {

  });

  it("(P3) Pool manager staking a pool", async function () {

  });

  it("(P4) Pool manager finalizing a pool", async function () {

  });

  it("(L1) Borrower creating a loan", async function () {

  });

  it("(P5) Provider depositing USDC to a pool", async function () {

  });

  it("(P6) Delegate funding a loan", async function () {

  });

  it("(P7) Liquidity provider withdrawing USDC", async function () {

  });

  it("(L2) Borrower posting collateral and drawing down Loan", async function () {

  });

  it("(P8) Liquidity pool claiming from loan", async function () {

  });

  it("(L3) Borrower making a single payment", async function () {

  });

  it("(P9) Liquidity pool claiming from loan", async function () {

  });

  it("(L4) Borrower making a full payment", async function () {

  });

  it("(P10) Liquidity pool claiming from loan ", async function () {

  });

  it("(P11) Liquidity provider withdrawing USDC from pool", async function () {

  });

});