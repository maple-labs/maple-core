const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");

describe("Pool Delegate Journey - DAI", function () {

  let LiquidityPoolAddress;

  it("A - Create a liquidity pool with DAI", async function () {

    const LiquidityPoolFactoryAddress = require("../../contracts/localhost/addresses/LiquidityPoolFactory.address");
    const LiquidityPoolFactoryABI = require("../../contracts/localhost/abis/LiquidityPoolFactory.abi");

    const DAIAddress = require("../../contracts/localhost/addresses/MintableTokenDAI.address.js");
    const USDCAddress = require("../../contracts/localhost/addresses/MintableTokenUSDC.address.js");
    const BPoolCreatorAddress = require("../../contracts/localhost/addresses/BCreator.address.js");
    const BPoolCreatorABI = require("../../contracts/localhost/abis/BCreator.abi.js");

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

    // Provide the following parameters in a form.
    const LIQUIDITY_ASSET = DAIAddress; // [DAIAddress, USDCAddress] are 2 options
    const STAKE_ASSET = BPoolAddress;
    const POOL_NAME = "LPDAI";
    const POOL_SYMBOL = "LPDAI";

    await LiquidityPoolFactory.createLiquidityPool(
      LIQUIDITY_ASSET,
      STAKE_ASSET,
      POOL_NAME,
      POOL_SYMBOL
    );

  });

  it("B - Mint the pool delegate some DAI", async function () {

    expect(true);

  });

  it("C - Fund the liquidity pool with DAI", async function () {

    expect(true);

  });

});
