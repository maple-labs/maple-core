const { expect, assert } = require("chai");
const artpath = "../../contracts/" + network.name + "/";

const MapleGlobalsAddress = require(artpath + "addresses/MapleGlobals.address");
const MapleGlobalsABI = require(artpath + "abis/MapleGlobals.abi");

const PoolFactoryAddress = require(artpath +
  "addresses/PoolFactory.address");
const PoolFactoryABI = require(artpath +
  "abis/PoolFactory.abi");

const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");
const BPoolCreatorAddress = require(artpath + "addresses/BCreator.address.js");
const BPoolCreatorABI = require(artpath + "abis/BCreator.abi.js");

describe("Pool Delegate Whitelist", function () {
  it("A - Governor can update validPoolDelegate in MapleGlobals", async function () {
    const accounts = await ethers.provider.listAccounts();

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0) // getSigner(0) == Governor
    );

    await MapleGlobals.setPoolDelegateWhitelist(accounts[1], false);

    const validityCheckOne = await MapleGlobals.validPoolDelegate(accounts[1]);
    expect(!validityCheckOne);

    await MapleGlobals.setPoolDelegateWhitelist(accounts[1], true);

    const validityCheckTwo = await MapleGlobals.validPoolDelegate(accounts[1]);
    expect(validityCheckTwo);
  });

  it("B - Non-governor may not update validPoolDelegate in MapleGlobals", async function () {
    const accounts = await ethers.provider.listAccounts();

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(1) // getSigner(1) != Governor
    );

    await expect(
      MapleGlobals.setPoolDelegateWhitelist(accounts[0], false)
    ).to.be.revertedWith("MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR");
  });

  it("C - Invalid pool delegate is prevented from creating a liquidity pool", async function () {
    const BPoolCreator = new ethers.Contract(
      BPoolCreatorAddress,
      BPoolCreatorABI,
      ethers.provider.getSigner(0)
    );

    BPoolAddress = await BPoolCreator.getBPoolAddress(0);

    PoolFactory = new ethers.Contract(
      PoolFactoryAddress,
      PoolFactoryABI,
      ethers.provider.getSigner(9) // getSigner(9) is not validated in whitelist in setup.js
    );

    const LIQUIDITY_ASSET = DAIAddress;
    const STAKE_ASSET = BPoolAddress;
    const STAKING_FEE_BASIS_POINTS = 0;
    const DELEGATE_FEE_BASIS_POINTS = 0;
    const POOL_NAME = "LPDAI";
    const POOL_SYMBOL = "LPDAI";

    await expect(
      PoolFactory.createPool(
        LIQUIDITY_ASSET,
        STAKE_ASSET,
        STAKING_FEE_BASIS_POINTS,
        DELEGATE_FEE_BASIS_POINTS
      )
    ).to.be.revertedWith(
      "PoolFactory::createPool:ERR_MSG_SENDER_NOT_WHITELISTED"
    );
  });

  it("D - Valid pool delegate can create a liquidity pool", async function () {
    const BPoolCreator = new ethers.Contract(
      BPoolCreatorAddress,
      BPoolCreatorABI,
      ethers.provider.getSigner(0)
    );

    BPoolAddress = await BPoolCreator.getBPoolAddress(0);

    PoolFactory = new ethers.Contract(
      PoolFactoryAddress,
      PoolFactoryABI,
      ethers.provider.getSigner(0) // getSigner(9) is not validated in whitelist in setup.js
    );

    const LIQUIDITY_ASSET = USDCAddress;
    const STAKE_ASSET = BPoolAddress;
    const STAKING_FEE_BASIS_POINTS = 0;
    const DELEGATE_FEE_BASIS_POINTS = 0;

    await PoolFactory.createPool(
      LIQUIDITY_ASSET,
      STAKE_ASSET,
      STAKING_FEE_BASIS_POINTS,
      DELEGATE_FEE_BASIS_POINTS
    );
  });
});
