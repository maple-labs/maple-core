const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const artpath = "../../contracts/" + network.name + "/";

describe.skip("Pool Delegate Journey - DAI", function () {
  let PoolAddress;
  let FundingAmount = 1000;

  it("Z - Fetch the list of liquidityTokens for pool creation", async function () {
    const MapleGlobalsAddress = require(artpath +
      "addresses/MapleGlobals.address");
    const MapleGlobalsABI = require(artpath + "abis/MapleGlobals.abi");

    let MapleGlobals;

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    const List = await MapleGlobals.getValidTokens();
  });

  it("A - Create a liquidity pool with DAI", async function () {
    const PoolFactoryAddress = require(artpath +
      "addresses/PoolFactory.address");
    const PoolFactoryABI = require(artpath +
      "abis/PoolFactory.abi");

    const DAIAddress = require(artpath +
      "addresses/MintableTokenDAI.address.js");
    const USDCAddress = require(artpath +
      "addresses/MintableTokenUSDC.address.js");
    const BPoolCreatorAddress = require(artpath +
      "addresses/BCreator.address.js");
    const BPoolCreatorABI = require(artpath + "abis/BCreator.abi.js");

    const BPoolCreator = new ethers.Contract(
      BPoolCreatorAddress,
      BPoolCreatorABI,
      ethers.provider.getSigner(0)
    );

    BPoolAddress = await BPoolCreator.getBPoolAddress(0);

    PoolFactory = new ethers.Contract(
      PoolFactoryAddress,
      PoolFactoryABI,
      ethers.provider.getSigner(0)
    );

    // For fetching the address of the pool (do not use this pattern in production).
    const preIncrementorValue = await PoolFactory.poolsCreated();

    // Provide the following parameters in a form.
    const LIQUIDITY_ASSET = DAIAddress; // [DAIAddress, USDCAddress] are 2 options, see Z for more.
    const STAKE_ASSET = BPoolAddress;
    const STAKING_FEE_BASIS_POINTS = 0;
    const DELEGATE_FEE_BASIS_POINTS = 0;
    const POOL_NAME = "LPDAI";
    const POOL_SYMBOL = "LPDAI";

    // Create the liquidity pool.
    await PoolFactory.createPool(
      LIQUIDITY_ASSET,
      STAKE_ASSET,
      STAKING_FEE_BASIS_POINTS,
      DELEGATE_FEE_BASIS_POINTS
    );

    PoolAddress = await PoolFactory.pools(
      preIncrementorValue
    );
  });

  it("B - Finalize the liquidity pool (enables deposits, confirms staking if any)", async function () {

    const PoolABI = require(artpath + "abis/Pool.abi.js");

    // Create liquidity pool
    Pool = new ethers.Contract(
      PoolAddress,
      PoolABI,
      ethers.provider.getSigner(0)
    );

    // Interface with Balancer Pool and stake
    let BPTStakeRequired = await Pool.getInitialStakeRequirements();

    const MapleGlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
    const MapleGlobalsAddress = require(artpath +"addresses/MapleGlobals.address.js");

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    MapleBPool = await MapleGlobals.mapleBPool();

    const BPoolABI = require(artpath + "abis/Pool.abi.js");

    BPool = new ethers.Contract(
      MapleBPool,
      BPoolABI,
      ethers.provider.getSigner(0)
    );

    const StakeLockerABI = require(artpath + "abis/StakeLocker.abi.js");
    const StakeLockerAddress = await Pool.stakeLocker();

    StakeLocker = new ethers.Contract(
      StakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    // Get stake required.
    // Stake 5% of the supply (should be enough for pulling out)
    // TODO: Complete calculator to fetch exact amount of poolAmountIn needed for staking.
    await BPool.approve(StakeLockerAddress, BigNumber.from(10).pow(18).mul(5));
    await StakeLocker.stake(BigNumber.from(10).pow(18).mul(5));

    // Finalize the pool
    await Pool.finalize();

  });

  it("C - Mint the pool delegate some DAI", async function () {
    const DAIAddress = require(artpath +
      "addresses/MintableTokenDAI.address.js");
    const DAIABI = require(artpath + "abis/MintableTokenDAI.abi");
    const accounts = await ethers.provider.listAccounts();

    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));

    // Mint DAI (auto-handles the wei conversion).
    await DAI.mintSpecial(accounts[1], FundingAmount);
  });

  it("D - Fund the liquidity pool with DAI", async function () {
    const PoolABI = require(artpath + "abis/Pool.abi.js");
    const DAIAddress = require(artpath +
      "addresses/MintableTokenDAI.address.js");
    const DAIABI = require(artpath + "abis/MintableTokenDAI.abi");

    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));

    Pool = new ethers.Contract(
      PoolAddress,
      PoolABI,
      ethers.provider.getSigner(0)
    );

    // BigNumber.from(base10).pow(asset_precision).mul(funding amount)
    const WEI_FUNDING_AMOUNT = BigNumber.from(10).pow(18).mul(FundingAmount);

    // Approve the liquidity pool (unique function call, may require another button).
    await DAI.approve(PoolAddress, WEI_FUNDING_AMOUNT);

    // Fund the liquidity pool.
    await Pool.deposit(WEI_FUNDING_AMOUNT);
  });
});
