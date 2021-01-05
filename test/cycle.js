const { expect, assert } = require("chai");
const artpath = "../../contracts/" + network.name + "/";

// Maple
const GlobalsAddress      = require(artpath + "addresses/MapleGlobals.address");
const GlobalsABI          = require(artpath + "abis/MapleGlobals.abi");
const PoolFactoryAddress  = require(artpath + "addresses/LiquidityPoolFactory.address");
const PoolFactoryABI      = require(artpath + "abis/LiquidityPoolFactory.abi");
const VaultFactoryAddress = require(artpath + "addresses/LoanVaultFactory.address");
const VaultFactoryABI     = require(artpath + "abis/LoanVaultFactory.abi");

// External
const BPoolABI            = require(artpath + "abis/BPool.abi");

describe("Full Cycle of Loan", function () {

  // Dynamic contracts, assigned values throughout test suite.
  let Pool, Vault, Asset;

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

  it("Pool_1 -> Pool Delegate initializes Liquidity Pool", async function () {

    const isFinalized = await BPool.isFinalized();

    console.log(isFinalized);

  });

  it("Pool_2 -> Pool Delegate stakes BPT tokens in StakeLocker", async function () {

  });

  it("Pool_3 -> Pool Delegate finalizes the Liquidity Pool", async function () {

  });

  it("Pool_4 -> Liquidity Providers deposit funds to Liquidity Pool", async function () {

  });

  it("Vault_1 -> Borrower initializes Loan Vault", async function () {

  });

  it("Pool_5 -> Pool Delegate funds the Loan Vault", async function () {

  });

  it("Vault_2 -> Borrower takes funding from Loan Vault", async function () {

  });

  it("Pool_6 -> Liquidity Pool claims any excess or fees from Loan Vault drawdown", async function () {

  });

  it("Vault_3 -> Borrower makes a single payment", async function () {

  });

  it("Pool_7 -> Liquidity Pool claims and distributes interest and principal from single payment", async function () {

  });

  it("Vault_4 -> Borrower makes another single payment", async function () {

  });

  it("Pool_8 -> Liquidity Pool claims and distributes interest and principal from single payment", async function () {

  });

  it("Vault_4 -> Borrower makes a full payment", async function () {

  });

  it("Pool_9 -> Liquidity Pool claims and distributes interest and principal from full payment", async function () {

  });

  it("Pool_10 -> Liquidity Providers withdraw funds from Liquidity Pool", async function () {

  });

});