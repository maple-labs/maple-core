const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const artpath = '../../contracts/' + network.name + '/';

describe("Pool Delegate Journey - DAI", function () {

  let LiquidityPoolAddress;
  let FundingAmount = 1000;

  it("Z - Fetch the list of liquidityTokens for pool creation", async function () {

    const MapleGlobalsAddress = require(artpath + "addresses/MapleGlobals.address");
    const MapleGlobalsABI = require(artpath + "abis/MapleGlobals.abi");

    let MapleGlobals;

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    const List = await MapleGlobals.getValidTokens();

    // The _validBorrowTokenAddresses / _validBorrowTokenSymbols list
    // can be used to generate a dropdown for viable "LIQUIDITY_ASSET" options.

    // console.log(
    //   List["_validBorrowTokenSymbols"],
    //   List["_validBorrowTokenAddresses"]
    // )

  });

  it("A - Create a liquidity pool with DAI", async function () {

    const LiquidityPoolFactoryAddress = require(artpath + "addresses/LiquidityPoolFactory.address");
    const LiquidityPoolFactoryABI = require(artpath + "abis/LiquidityPoolFactory.abi");

    const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
    const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");
    const BPoolCreatorAddress = require(artpath + "addresses/BCreator.address.js");
    const BPoolCreatorABI = require(artpath + "abis/BCreator.abi.js");

    const BPoolCreator = new ethers.Contract(
      BPoolCreatorAddress,
      BPoolCreatorABI,
      ethers.provider.getSigner(0)
    );

    BPoolAddress = await BPoolCreator.getBPoolAddress(0);

    LiquidityPoolFactory = new ethers.Contract(
      LiquidityPoolFactoryAddress,
      LiquidityPoolFactoryABI,
      ethers.provider.getSigner(0)
    );

    // For fetching the address of the pool (do not use this pattern in production).
    const preIncrementorValue = await LiquidityPoolFactory.liquidityPoolsCreated();

    // Provide the following parameters in a form.
    const LIQUIDITY_ASSET = DAIAddress; // [DAIAddress, USDCAddress] are 2 options, see Z for more.
    const STAKE_ASSET = BPoolAddress;
    const POOL_NAME = "LPDAI";
    const POOL_SYMBOL = "LPDAI";

    // Create the liquidity pool.
    await LiquidityPoolFactory.createLiquidityPool(
      LIQUIDITY_ASSET,
      STAKE_ASSET,
      POOL_NAME,
      POOL_SYMBOL
    );

    LiquidityPoolAddress = await LiquidityPoolFactory.getLiquidityPool(preIncrementorValue);

  });

  it("B - Finalize the liquidity pool (enables deposits, confirms staking if any)", async function () {

    const LiquidityPoolABI = require(artpath + "abis/LiquidityPool.abi.js");

    LiquidityPool = new ethers.Contract(
      LiquidityPoolAddress,
      LiquidityPoolABI,
      ethers.provider.getSigner(0)
    )

    // Finalize the pool
    await LiquidityPool.finalize();
    
  });

  it("C - Mint the pool delegate some DAI", async function () {

    const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
    const DAIABI = require(artpath + "abis/MintableTokenDAI.abi");
    const accounts = await ethers.provider.listAccounts();
    
    DAI = new ethers.Contract(
      DAIAddress,
      DAIABI,
      ethers.provider.getSigner(0)
    );

    // Mint DAI (auto-handles the wei conversion).
    await DAI.mintSpecial(accounts[1], FundingAmount);

  });

  it("D - Fund the liquidity pool with DAI", async function () {

    const LiquidityPoolABI = require(artpath + "abis/LiquidityPool.abi.js");
    const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
    const DAIABI = require(artpath + "abis/MintableTokenDAI.abi");

    DAI = new ethers.Contract(
      DAIAddress,
      DAIABI,
      ethers.provider.getSigner(0)
    );

    LiquidityPool = new ethers.Contract(
      LiquidityPoolAddress,
      LiquidityPoolABI,
      ethers.provider.getSigner(0)
    )

    // BigNumber.from(base10).pow(asset_precision).mul(funding amount)
    const WEI_FUNDING_AMOUNT = BigNumber.from(10).pow(18).mul(FundingAmount);

    // Approve the liquidity pool (unique function call, may require another button).
    await DAI.approve(LiquidityPoolAddress, WEI_FUNDING_AMOUNT);

    // Fund the liquidity pool.
    await LiquidityPool.deposit(WEI_FUNDING_AMOUNT);
    
  });

});
