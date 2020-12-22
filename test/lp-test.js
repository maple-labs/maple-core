const { expect } = require("chai");
const { BigNumber } = require("ethers");
const artpath = '../../src/' + network.name + '/';

const DAIABI = require(artpath + "abis/MintableTokenDAI.abi.js");
const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
const USDCABI = require(artpath + "abis/MintableTokenUSDC.abi.js");
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");

const MPLGlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
const MPLGlobalsAddress = require(artpath + "addresses/MapleGlobals.address.js");
const MapleGlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
const MapleGlobalsAddress = require(artpath + "addresses/MapleGlobals.address.js");

const StakeLockerFactoryABI = require(artpath + "abis/StakeLockerFactory.abi.js");
const StakeLockerFactoryAddress = require(artpath + "addresses/StakeLockerFactory.address.js");
const StakeLockerABI = require(artpath + "abis/StakeLocker.abi.js");
const LiquidityLockerFactoryABI = require(artpath + "abis/LiquidityLockerFactory.abi.js");
const LiquidityLockerFactoryAddress = require(artpath + "addresses/LiquidityLockerFactory.address.js");
const LiquidityLockerABI = require(artpath + "abis/LiquidityLocker.abi.js");

const BPoolCreatorAddress = require(artpath + "addresses/BCreator.address.js");
const BPoolCreatorABI = require(artpath + "abis/BCreator.abi.js");
const BPoolABI = require(artpath + "abis/BPool.abi.js");
const LPFactoryABI = require(artpath + "abis/LiquidityPoolFactory.abi.js");
const LPFactoryAddress = require(artpath + "addresses/LiquidityPoolFactory.address.js");
const LPABI = require(artpath + "abis/LiquidityPool.abi.js");
const LiquidityPoolABI = require(artpath + "abis/LiquidityPool.abi.js");
const LVFactoryABI = require(artpath + "abis/LoanVaultFactory.abi.js");
const LVFactoryAddress = require(artpath + "addresses/LoanVaultFactory.address.js");

describe("LiquidityPool & LiquidityLocker & StakeLocker", function () {

  let LiquidityPoolAddressDAI, LiquidityPoolAddressUSDC;
  let LiquidityPoolDAI, LiquidityPoolUSDC;
  let StakeLockerDAI, StakeLockerUSDC;
  let LiquidityLockerDAI, LiquidityLockerUSDC;
  let MapleBPool;
  let accounts;

  before(async () => {
    accounts = await ethers.provider.listAccounts();
  });

  it("A - Create two stablecoin liquidity pools, DAI & USDC", async function () {

    // Liquidity pool factory object.
    const LiquidityPoolFactoryAddress = require(artpath + "addresses/LiquidityPoolFactory.address");
    const LiquidityPoolFactoryABI = require(artpath + "abis/LiquidityPoolFactory.abi");

    LiquidityPoolFactory = new ethers.Contract(
      LiquidityPoolFactoryAddress,
      LiquidityPoolFactoryABI,
      ethers.provider.getSigner(0)
    );

    const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
    const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");

    // Get official Maple balancer pool.
    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    MapleBPool = await MapleGlobals.mapleBPool();

    // For fetching the address of the pool (do not use this pattern in production).
    const INDEX_DAI = await LiquidityPoolFactory.liquidityPoolsCreated();

    // Create DAI pool (these variables could be used in a form).
    let LIQUIDITY_ASSET = DAIAddress; // [DAIAddress, USDCAddress] are 2 options, see Z for more.
    let STAKE_ASSET = MapleBPool;
    let STAKING_FEE_BASIS_POINTS = 0;
    let DELEGATE_FEE_BASIS_POINTS = 0;
    let POOL_NAME = "MAPLEALPHA/DAI";
    let POOL_SYMBOL = "LP-DAI-" + INDEX_DAI.toString();

    await LiquidityPoolFactory.createLiquidityPool(
      LIQUIDITY_ASSET,
      STAKE_ASSET,
      STAKING_FEE_BASIS_POINTS,
      DELEGATE_FEE_BASIS_POINTS,
      POOL_NAME,
      POOL_SYMBOL
    );
    
    LiquidityPoolAddressDAI = await LiquidityPoolFactory.getLiquidityPool(INDEX_DAI);

    const INDEX_USDC = await LiquidityPoolFactory.liquidityPoolsCreated();

    // Create USDC pool (these variables could be used in a form).
    LIQUIDITY_ASSET = USDCAddress;
    STAKE_ASSET = MapleBPool;
    STAKING_FEE_BASIS_POINTS = 0;
    DELEGATE_FEE_BASIS_POINTS = 0;
    POOL_NAME = "MAPLEALPHA/USDC"
    POOL_SYMBOL = "LP-USDC-" + INDEX_USDC.toString();

    await LiquidityPoolFactory.createLiquidityPool(
      LIQUIDITY_ASSET,
      STAKE_ASSET,
      STAKING_FEE_BASIS_POINTS,
      DELEGATE_FEE_BASIS_POINTS,
      POOL_NAME,
      POOL_SYMBOL
    );

    LiquidityPoolAddressUSDC = await LiquidityPoolFactory.getLiquidityPool(INDEX_USDC);
    
    LiquidityPoolDAI = new ethers.Contract(
      LiquidityPoolAddressDAI,
      LiquidityPoolABI,
      ethers.provider.getSigner(0)
    );

    LiquidityPoolUSDC = new ethers.Contract(
      LiquidityPoolAddressUSDC,
      LiquidityPoolABI,
      ethers.provider.getSigner(0)
    );

    StakeLockerDAI = await LiquidityPoolDAI.stakeLockerAddress();
    StakeLockerUSDC = await LiquidityPoolUSDC.stakeLockerAddress();

    LiquidityLockerDAI = await LiquidityPoolDAI.liquidityLockerAddress();
    LiquidityLockerUSDC = await LiquidityPoolUSDC.liquidityLockerAddress();

  });

  it("B - Ensure correct LP is assigned to StakeLocker and LiquidityLocker", async function () {

    StakeLockerFactory = new ethers.Contract(
      StakeLockerFactoryAddress,
      StakeLockerFactoryABI,
      ethers.provider.getSigner(0)
    );

    LiquidityLockerFactory = new ethers.Contract(
      LiquidityLockerFactoryAddress,
      LiquidityLockerFactoryABI,
      ethers.provider.getSigner(0)
    );

    const DAI_STAKE_LOCKER_ADDRESS = await LiquidityPoolDAI.stakeLockerAddress();
    const USDC_STAKE_LOCKER_ADDRESS = await LiquidityPoolUSDC.stakeLockerAddress();
    const DAI_LIQUIDITY_LOCKER_ADDRESS = await LiquidityPoolDAI.liquidityLockerAddress();
    const USDC_LIQUIDITY_LOCKER_ADDRESS = await LiquidityPoolUSDC.liquidityLockerAddress();

    // Check the StakeLockerFactory
    const DAI_STAKE_LOCKER_OWNER = await StakeLockerFactory.getOwner(DAI_STAKE_LOCKER_ADDRESS);
    const USDC_STAKE_LOCKER_OWNER = await StakeLockerFactory.getOwner(USDC_STAKE_LOCKER_ADDRESS);
    expect(DAI_STAKE_LOCKER_OWNER).to.equal(LiquidityPoolAddressDAI);
    expect(USDC_STAKE_LOCKER_OWNER).to.equal(LiquidityPoolAddressUSDC);

    // Check the LiquidityLockerFactory
    const DAI_LIQUIDITY_LOCKER_OWNER = await LiquidityLockerFactory.getOwner(DAI_LIQUIDITY_LOCKER_ADDRESS);
    const USDC_LIQUIDITY_LOCKER_OWNER = await LiquidityLockerFactory.getOwner(USDC_LIQUIDITY_LOCKER_ADDRESS);
    expect(DAI_LIQUIDITY_LOCKER_OWNER).to.equal(LiquidityPoolAddressDAI);
    expect(USDC_LIQUIDITY_LOCKER_OWNER).to.equal(LiquidityPoolAddressUSDC);

    // Check that both LiquidityLocker and StakeLocker isValidLocker
    const VALID_DAI_STAKE_LOCKER = await StakeLockerFactory.isStakeLocker(DAI_STAKE_LOCKER_ADDRESS)
    const VALID_USDC_STAKE_LOCKER = await StakeLockerFactory.isStakeLocker(USDC_STAKE_LOCKER_ADDRESS)
    const VALID_DAI_LIQUIDITY_LOCKER = await LiquidityLockerFactory.isLiquidityLocker(DAI_LIQUIDITY_LOCKER_ADDRESS)
    const VALID_USDC_LIQUIDITY_LOCKER = await LiquidityLockerFactory.isLiquidityLocker(USDC_LIQUIDITY_LOCKER_ADDRESS)

    expect(VALID_DAI_STAKE_LOCKER)
    expect(VALID_USDC_STAKE_LOCKER)
    expect(VALID_DAI_LIQUIDITY_LOCKER)
    expect(VALID_USDC_LIQUIDITY_LOCKER)

  });

  it("C - Check pools are not finalized", async function () {

    let isFinalizedDAI = await LiquidityPoolDAI.isFinalized();
    let isFinalizedUSDC = await LiquidityPoolUSDC.isFinalized();

    expect(!isFinalizedDAI)
    expect(!isFinalizedUSDC)

  });

  it("D - Set global stake requirement to <CUSTOM>", async function () {

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    await MapleGlobals.setStakeRequired(100000 * 10**6);

  });

  it("E - Fail finalization (stake must be deposited before finalization)", async function () {

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    const STAKE_REQUIRED = await MapleGlobals.stakeAmountRequired();
    
    // If STAKE_REQUIRED == 0, finalization will pass without any stake deposited.
    // If STAKE_REQUIRED > 0, finalization will fail without any stake deposited. 
    if (parseInt(STAKE_REQUIRED["_hex"]) == 0) {
      expect(true);
    }
    else {
      await expect(
        LiquidityPoolDAI.finalize()
      ).to.be.revertedWith("LiquidityPool::finalize:ERR_NOT_ENOUGH_STAKE")
      await expect(
        LiquidityPoolUSDC.finalize()
      ).to.be.revertedWith("LiquidityPool::finalize:ERR_NOT_ENOUGH_STAKE")
    }

    let isFinalizedDAI = await LiquidityPoolDAI.isFinalized();
    let isFinalizedUSDC = await LiquidityPoolUSDC.isFinalized();

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    expect(!isFinalizedDAI)
    expect(!isFinalizedUSDC)

  });

  it("F - Stake the pools, if necessary", async function () {

    let BPTStakeRequiredDAI = await LiquidityPoolDAI.getInitialStakeRequirements();
    let BPTStakeRequiredUSDC = await LiquidityPoolUSDC.getInitialStakeRequirements();

    expect(!BPTStakeRequiredDAI[2])
    expect(!BPTStakeRequiredUSDC[2])

    // console.log(parseInt(BPTStakeRequiredDAI[0]["_hex"]))
    // console.log(parseInt(BPTStakeRequiredDAI[1]["_hex"]))
    // console.log(parseInt(BPTStakeRequiredDAI[3]["_hex"]))
    // console.log(parseInt(BPTStakeRequiredDAI[4]["_hex"]))

    BPool = new ethers.Contract(
      MapleBPool,
      BPoolABI,
      ethers.provider.getSigner(0)
    );

    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    // Get stake required.

    // Stake 5% of the supply (should be enough for pulling out)
    // TODO: Complete calculator to fetch exact amount of poolAmountIn needed for staking.
    await BPool.approve(StakeLockerDAI, BigNumber.from(10).pow(18).mul(5));
    await StakeLockerDAIPool.stake(BigNumber.from(10).pow(18).mul(5));

    await BPool.approve(StakeLockerUSDC, BigNumber.from(10).pow(18).mul(5));
    await StakeLockerUSDCPool.stake(BigNumber.from(10).pow(18).mul(5));

    BPTStakeRequiredDAI = await LiquidityPoolDAI.getInitialStakeRequirements();
    BPTStakeRequiredUSDC = await LiquidityPoolUSDC.getInitialStakeRequirements();

    // console.log(parseInt(BPTStakeRequiredUSDC[0]["_hex"]))
    // console.log(parseInt(BPTStakeRequiredUSDC[1]["_hex"]))
    // console.log(parseInt(BPTStakeRequiredUSDC[3]["_hex"]))
    // console.log(parseInt(BPTStakeRequiredUSDC[4]["_hex"]))


    expect(BPTStakeRequiredDAI[2])
    expect(BPTStakeRequiredUSDC[2])

    // console.log(parseInt(BPTStakeRequiredDAI[0]["_hex"]))
    // console.log(parseInt(BPTStakeRequiredDAI[1]["_hex"]))
    // console.log(parseInt(BPTStakeRequiredDAI[3]["_hex"]))
    // console.log(parseInt(BPTStakeRequiredDAI[4]["_hex"]))

  });

  it("G - Allow delegate to unstake partial before finalization", async function () {

    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    BPool = new ethers.Contract(
      MapleBPool,
      BPoolABI,
      ethers.provider.getSigner(0)
    );

    // Unstake 1 wei BPT
    await StakeLockerDAIPool.unstake(1);
    await StakeLockerUSDCPool.unstake(1);

  });

  it("H - Prevent liquidity locker deposits before finalization", async function () {

    await expect(
      LiquidityPoolDAI.deposit(1)
    ).to.be.revertedWith("LiquidityPool:ERR_NOT_FINALIZED")
    
    await expect(
      LiquidityPoolUSDC.deposit(1)
    ).to.be.revertedWith("LiquidityPool:ERR_NOT_FINALIZED")

  });

  it("I - Finalize liquidity pools (enable deposits)", async function () {

    await LiquidityPoolDAI.finalize();
    await LiquidityPoolUSDC.finalize();

  });

  it("J - Accounting, ensure BPT balance is same as StakeLocker balance", async function () {

    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    BPool = new ethers.Contract(
      MapleBPool,
      BPoolABI,
      ethers.provider.getSigner(0)
    );

    const StakeLockerFDTBalanceDAI = await StakeLockerDAIPool.balanceOf(accounts[0])
    const StakeLockerFDTBalanceUSDC = await StakeLockerDAIPool.balanceOf(accounts[0])
    const BPoolBalanceDAI = await BPool.balanceOf(StakeLockerDAI)
    const BPoolBalanceUSDC = await BPool.balanceOf(StakeLockerUSDC)

    expect(
      parseInt(StakeLockerFDTBalanceDAI["_hex"])
    ).to.equals(
      parseInt(BPoolBalanceDAI["_hex"])
    )
    expect(
      parseInt(StakeLockerFDTBalanceUSDC["_hex"])
    ).to.equals(
      parseInt(BPoolBalanceUSDC["_hex"])
    )

  });

  it("K - Random user can not transfer LiquidityLocker assets", async function () {
    
    LiquidityLockerDAIPool = new ethers.Contract(
      LiquidityLockerDAI,
      LiquidityLockerABI,
      ethers.provider.getSigner(0)
    );

    LiquidityLockerUSDCPool = new ethers.Contract(
      LiquidityLockerUSDC,
      LiquidityLockerABI,
      ethers.provider.getSigner(0)
    );

    await expect(
      LiquidityLockerDAIPool.transfer(accounts[0], 0)
    ).to.be.revertedWith(
      "LiquidityLocker:ERR_MSG_SENDER_NOT_OWNER"
    );

    await expect(
      LiquidityLockerUSDCPool.transfer(accounts[0], 0)
    ).to.be.revertedWith(
      "LiquidityLocker:ERR_MSG_SENDER_NOT_OWNER"
    );

  });

  it("L - Provide liquidity to pools, ensure proper amount of FDTs minted", async function () {
    
    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));
    USDC = new ethers.Contract(USDCAddress, USDCABI, ethers.provider.getSigner(0));

    const DEPOSIT_AMT = 1000;
    const DAI_DEPOSIT_AMT = BigNumber.from(10).pow(18).mul(DEPOSIT_AMT); // 1000 DAI deposit
    const USDC_DEPOSIT_AMT = BigNumber.from(10).pow(6).mul(DEPOSIT_AMT); // 1000 USDC deposit

    await DAI.approve(LiquidityPoolAddressDAI, DAI_DEPOSIT_AMT)
    await USDC.approve(LiquidityPoolAddressUSDC, USDC_DEPOSIT_AMT)
    await LiquidityPoolDAI.deposit(DAI_DEPOSIT_AMT)
    await LiquidityPoolUSDC.deposit(USDC_DEPOSIT_AMT)

    const FDTBalanceDAILP = await LiquidityPoolDAI.balanceOf(accounts[0])
    const FDTBalanceUSDCLP = await LiquidityPoolUSDC.balanceOf(accounts[0])
    
    // FDTs = 18 decimals, USDC = 6 decimals
    expect(parseInt(FDTBalanceDAILP["_hex"])).to.equals(parseInt(DAI_DEPOSIT_AMT["_hex"]))
    expect(parseInt(FDTBalanceUSDCLP["_hex"])).to.equals(parseInt(BigNumber.from(10).pow(18).mul(DEPOSIT_AMT)))

  });

  it("M - Outside party can stake BPTs within StakeLocker", async function () {

    BPool = new ethers.Contract(
      MapleBPool,
      BPoolABI,
      ethers.provider.getSigner(3)
    );

    USDC = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(3)
    )

    await USDC.mintSpecial(accounts[3], 15000);
    await USDC.approve(MapleBPool, BigNumber.from(10).pow(6).mul(10000))

    await BPool.joinswapExternAmountIn(USDCAddress, BigNumber.from(10).pow(6).mul(10000), 0);

    const poolSharesMinted = await BPool.balanceOf(accounts[3])
    const poolSharesMintedFix = parseInt(poolSharesMinted["_hex"])

    await BPool.approve(StakeLockerDAI, poolSharesMintedFix / 2)
    await BPool.approve(StakeLockerUSDC, poolSharesMintedFix / 2)

    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(3)
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(3)
    );

    await StakeLockerDAIPool.stake(poolSharesMintedFix / 2);
    await StakeLockerUSDCPool.stake(poolSharesMintedFix / 2);

  });

  it("N - Prevent unstaking when outside party attempts unstake (unstakeDelay)", async function () {

    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(3)
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(3)
    );

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0) // getSigner(0) == Admin
    );

    await MapleGlobals.setUnstakeDelay("999999999999999999");

    const FDTBalanceDAILP = await StakeLockerDAIPool.balanceOf(accounts[3])
    const FDTBalanceUSDCLP = await StakeLockerUSDCPool.balanceOf(accounts[3])

    await expect(
      StakeLockerDAIPool.unstake(FDTBalanceDAILP)
    ).to.be.revertedWith(
      "Stakelocker:ERR_AMT_REQUESTED_UNAVAILABLE"
    );
    await expect(
      StakeLockerUSDCPool.unstake(FDTBalanceUSDCLP)
    ).to.be.revertedWith(
      "Stakelocker:ERR_AMT_REQUESTED_UNAVAILABLE"
    );

    await MapleGlobals.setUnstakeDelay("0");

  });

  it("O - Outside party can unstake when unstakeDelay == 0, receives BPTs in return", async function () {
    
    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(3)
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(3)
    );

    BPool = new ethers.Contract(
      MapleBPool,
      BPoolABI,
      ethers.provider.getSigner(3)
    );

    const FDTBalanceDAIStakeLocker = await StakeLockerDAIPool.balanceOf(accounts[3])
    const FDTBalanceUSDCStakeLocker = await StakeLockerUSDCPool.balanceOf(accounts[3])

    const preBPTBalanceDAI = await BPool.balanceOf(accounts[3])
    const preBPTBalanceUSDC = await BPool.balanceOf(accounts[3])

    await StakeLockerDAIPool.unstake(parseInt(FDTBalanceDAIStakeLocker["_hex"]) / 2);
    await StakeLockerUSDCPool.unstake(parseInt(FDTBalanceUSDCStakeLocker["_hex"]) / 2);

    const postBPTBalanceDAI = await BPool.balanceOf(accounts[3])
    const postBPTBalanceUSDC = await BPool.balanceOf(accounts[3])
    
    // TODO: Correct precision / decimals.
    expect(
      parseInt(preBPTBalanceDAI["_hex"])
    ).to.be.lessThan(
      parseInt(postBPTBalanceDAI["_hex"])
    )
    expect(
      parseInt(preBPTBalanceUSDC["_hex"])
    ).to.be.lessThan(
      parseInt(postBPTBalanceUSDC["_hex"])
    )

  });

  it("P - Check isDefunct() for pools equals false", async function () {

    DAIPoolDefunct = await LiquidityPoolDAI.isDefunct();
    USDCPoolDefunct = await LiquidityPoolUSDC.isDefunct();

    expect(!DAIPoolDefunct)
    expect(!USDCPoolDefunct)
    
  });

  it("Q - Delegate may not unstake after finalization", async function () {
    
    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    await expect(
      StakeLockerDAIPool.unstake(1)
    ).to.be.revertedWith(
      "StakeLocker:ERR_DELEGATE_STAKE_LOCKED"
    );

    await expect(
      StakeLockerUSDCPool.unstake(1)
    ).to.be.revertedWith(
      "StakeLocker:ERR_DELEGATE_STAKE_LOCKED"
    );

  });

  it("R - Pool delegate may not transfer FDTs", async function () {

    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(0) // getSigner(0) = Pool Delegate
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );

    await expect(
      StakeLockerDAIPool.transfer(accounts[2], 100)
    ).to.be.revertedWith(
      "StakeLocker:ERR_DELEGATE_STAKE_LOCKED"
    );
    
    await expect(
      StakeLockerUSDCPool.transfer(accounts[2], 100)
    ).to.be.revertedWith(
      "StakeLocker:ERR_DELEGATE_STAKE_LOCKED"
    );

  });

  it("S - Support partial unstake from a StakeLocker", async function () {
    
    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(3)
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(3)
    );

    BPool = new ethers.Contract(
      MapleBPool,
      BPoolABI,
      ethers.provider.getSigner(3)
    );

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0) // getSigner(0) == Admin
    );

    // Set stake delay above 0.
    const STAKE_DELAY = 10;
    await MapleGlobals.setUnstakeDelay(0);

    const BPTBalance = await BPool.balanceOf(accounts[3]);
    const WithdrawableBPTDAI = await StakeLockerDAIPool.getUnstakeableBalance(accounts[3]);
    const WithdrawableBPTUSDC = await StakeLockerUSDCPool.getUnstakeableBalance(accounts[3]);

    await StakeLockerDAIPool.unstake(parseInt(WithdrawableBPTDAI["_hex"] / 2));
    await StakeLockerUSDCPool.unstake(parseInt(WithdrawableBPTUSDC["_hex"] / 2));

    // ~ SAVE LINES BELOW FOR FUTURE REFERENCE ~

    // await new Promise((r) => setTimeout(r, 2000));
    // this is because the denominator has a +1 to prevent div by 0
    // double precision arithmatic truncation error means we will get inaccuracy after about 15 digits
    // expect(Math.abs(ubal / bal - 2 / (stakeDelay + 1)) < 10 ** -15);

  });

  it("T - Users may withdraw interest via withdrawFunds() FDT(ERC-2222) in StakeLockers", async function () {
    
    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(3)
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(3)
    );

    DAI = new ethers.Contract(
      DAIAddress,
      DAIABI,
      ethers.provider.getSigner(3)
    )

    USDC = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(3)
    )

    // Mint the StakeLockers the respective tokens.
    await DAI.mintSpecial(StakeLockerDAI, 15000);
    await USDC.mintSpecial(StakeLockerUSDC, 15000);
    
    await StakeLockerDAIPool.updateFundsReceived();
    await StakeLockerUSDCPool.updateFundsReceived();
    
    await StakeLockerDAIPool.withdrawFunds();
    await StakeLockerUSDCPool.withdrawFunds();

    // TODO: More tests on precise accounting here.

  });

  it("U - Prevent non-admin users from calling admin commands for lockers", async function () {
    
    StakeLockerDAIPool = new ethers.Contract(
      StakeLockerDAI,
      StakeLockerABI,
      ethers.provider.getSigner(2)
    );

    StakeLockerUSDCPool = new ethers.Contract(
      StakeLockerUSDC,
      StakeLockerABI,
      ethers.provider.getSigner(2)
    );

    await expect(
      StakeLockerDAIPool.deleteLP()
    ).to.be.revertedWith(
      "StakeLocker:ERR_UNAUTHORIZED"
    );

    await expect(
      StakeLockerDAIPool.finalizeLP()
    ).to.be.revertedWith(
      "StakeLocker:ERR_UNAUTHORIZED"
    );

    await expect(
      StakeLockerUSDCPool.deleteLP()
    ).to.be.revertedWith(
      "StakeLocker:ERR_UNAUTHORIZED"
    );

    await expect(
      StakeLockerUSDCPool.finalizeLP()
    ).to.be.revertedWith(
      "StakeLocker:ERR_UNAUTHORIZED"
    );

  });

  // TODO:  Create a new test suite for funding loans.
  //        This file should be restricuted to pool and locker instantiation.

  it("V - Reset global stake requirement to 0", async function () {

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    await MapleGlobals.setStakeRequired(0);

  });

});
