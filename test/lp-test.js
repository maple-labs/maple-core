const { expect } = require("chai");
const BigNumber = require("bignumber.js"); // TODO: Adjust this test to use the ether.js BigNumber type.

const DAIABI = require("../../contracts/localhost/abis/MintableTokenDAI.abi.js");
const DAIAddress = require("../../contracts/localhost/addresses/MintableTokenDAI.address.js");
const USDCABI = require("../../contracts/localhost/abis/MintableTokenUSDC.abi.js");
const USDCAddress = require("../../contracts/localhost/addresses/MintableTokenUSDC.address.js");

const MPLGlobalsABI = require("../../contracts/localhost/abis/MapleGlobals.abi.js");
const MPLGlobalsAddress = require("../../contracts/localhost/addresses/MapleGlobals.address.js");

const StakeLockerFactoryABI = require("../../contracts/localhost/abis/LPStakeLockerFactory.abi.js");
const StakeLockerFactoryAddress = require("../../contracts/localhost/addresses/LPStakeLockerFactory.address.js");
const StakeLockerABI = require("../../contracts/localhost/abis/LPStakeLocker.abi.js");
const LiquidityLockerFactoryABI = require("../../contracts/localhost/abis/LiquidityLockerFactory.abi.js");
const LiquidityLockerFactoryAddress = require("../../contracts/localhost/addresses/LiquidityLockerFactory.address.js");
const LiquidityLockerABI = require("../../contracts/localhost/abis/LiquidityLocker.abi.js");

const BPoolCreatorAddress = require("../../contracts/localhost/addresses/BCreator.address.js");
const BPoolCreatorABI = require("../../contracts/localhost/abis/BCreator.abi.js");
const BPoolABI = require("../../contracts/localhost/abis/BPool.abi.js");
const LPFactoryABI = require("../../contracts/localhost/abis/LPFactory.abi.js");
const LPFactoryAddress = require("../../contracts/localhost/addresses/LPFactory.address.js");
const LPABI = require("../../contracts/localhost/abis/LiquidityPool.abi.js");
const LVFactoryABI = require("../../contracts/localhost/abis/LoanVaultFactory.abi.js");
const LVFactoryAddress = require("../../contracts/localhost/addresses/LoanVaultFactory.address.js");

// TODO: Adjust this test to use the ether.js BigNumber type.

describe("LiquidityPool + LiquidityLocker + StakeLocker", function () {

  let DAILP, USDCLP;
  
  before(async () => {
    accounts = await ethers.provider.listAccounts();
    MPLGlobals = new ethers.Contract(
      MPLGlobalsAddress,
      MPLGlobalsABI,
      ethers.provider.getSigner(0)
    );
    LPFactory = new ethers.Contract(
      LPFactoryAddress,
      LPFactoryABI,
      ethers.provider.getSigner(0)
    );
    StakeLockerFactory = new ethers.Contract(
      StakeLockerFactoryAddress,
      StakeLockerFactoryABI,
      ethers.provider.getSigner(0)
    );
    USDC = new ethers.Contract(USDCAddress, USDCABI, ethers.provider.getSigner(0));
    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));
    const BPoolCreator = new ethers.Contract(
      BPoolCreatorAddress,
      BPoolCreatorABI,
      ethers.provider.getSigner(0)
    );
    DAIBPoolAddress = await BPoolCreator.getBPoolAddress(0);
    USDCBPoolAddress = await BPoolCreator.getBPoolAddress(1);
    await LPFactory.createLiquidityPool(
      DAIAddress,
      DAIBPoolAddress,
      StakeLockerFactoryAddress,
      LiquidityLockerFactoryAddress,
      "Maple DAI LP",
      "LPDAI",
      MPLGlobalsAddress
    );
    await LPFactory.createLiquidityPool(
      USDCAddress,
      USDCBPoolAddress,
      StakeLockerFactoryAddress,
      LiquidityLockerFactoryAddress,
      "Maple USDC LP",
      "LPUSDC",
      MPLGlobalsAddress
    );
    DAILPAddress = await LPFactory.getLiquidityPool(0);
    USDCLPAddress = await LPFactory.getLiquidityPool(1);
    DAILP = new ethers.Contract(
      DAILPAddress,
      LPABI,
      ethers.provider.getSigner(0)
    );
    USDCLP = new ethers.Contract(
      USDCLPAddress,
      LPABI,
      ethers.provider.getSigner(0)
    );
    LALockerFactory = new ethers.Contract(
      LiquidityLockerFactoryAddress,
      LiquidityLockerFactoryABI,
      ethers.provider.getSigner(0)
    );
    DAIStakeLockerAddress = await DAILP.stakeLockerAddress();
    USDCStakeLockerAddress = await USDCLP.stakeLockerAddress();
  });

  it("Sets the correct owners for Token Lockers", async function () {
    const DAILockerowner = await StakeLockerFactory.getPool(DAIStakeLockerAddress);
    const USDCLockerowner = await StakeLockerFactory.getPool(
      USDCStakeLockerAddress
    );
    expect(DAILockerowner).to.equal(DAILPAddress);
    expect(USDCLockerowner).to.equal(USDCLPAddress);
  });

  it("is not finalized", async function () {
    isfinDAI = await DAILP.isFinalized();
    isfinUSDC = await USDCLP.isFinalized();
    expect(isfinDAI).to.equal(false);
    expect(isfinUSDC).to.equal(false);
  });

  it("Can not finalize DAI pool without stake", async function () {
    await expect(DAILP.finalize()).to.be.revertedWith(
      "FDT_LP.makeStakeLocker: NOT_ENOUGH_STAKE"
    );
    isfin = await DAILP.isFinalized();
    expect(isfin.toString()).to.equal("false");
  });

  it("Can deposit stake DAI", async function () {
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    );
    const DAILocker = new ethers.Contract(
      DAIStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );
    await DAIBPool.approve(DAIStakeLockerAddress, "100000000000000000000");
    await DAILocker.stake("100000000000000000000");
  });

  it("delegate can unstake BEFORE FINALIZE", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    );

    const daibal = await DAIBPool.balanceOf(accounts[0]);
    await DAIStakeLocker.unstake(100);
    const daibal2 = await DAIBPool.balanceOf(accounts[0]);
    expect(daibal2 - daibal).to.equal(100);
  });

  it("Can not deposit into DAI liquidity pool before it is finalized", async function () {
    const money = 1;
    const dec = BigInt(await DAI.decimals());
    const moneyDAI = BigInt(money) * BigInt(10) ** dec;
    const moneyInWEI = BigInt(money) * BigInt(10) ** BigInt(18);
    await DAI.approve(DAILP.address, moneyDAI);
    await expect(DAILP.deposit(moneyDAI)).to.be.revertedWith(
      "LiquidityPool: IS NOT FINALIZED"
    );
  });

  it("Can not deposit into USDC liquidity pool before it is finalized", async function () {
    const money = 1;
    const dec = BigInt(await USDC.decimals());
    const moneyUSDC = BigInt(money) * BigInt(10) ** dec;
    const moneyInWEI = BigInt(money) * BigInt(10) ** BigInt(18);
    await USDC.approve(USDCLP.address, moneyUSDC);
    await expect(USDCLP.deposit(moneyUSDC)).to.be.revertedWith(
      "LiquidityPool: IS NOT FINALIZED"
    );
  });

  it("Can finalize DAI pool with stake", async function () {
    await DAILP.finalize();
    isfin = await DAILP.isFinalized();
    expect(isfin.toString()).to.equal("true");
  });

  it("Can not finalize USDC pool without stake", async function () {
    await expect(USDCLP.finalize()).to.be.revertedWith(
      "FDT_LP.makeStakeLocker: NOT_ENOUGH_STAKE"
    );
    isfin = await USDCLP.isFinalized();
    expect(isfin.toString()).to.equal("false");
  });

  it("Can deposit stake USDC", async function () {
    const USDCBPool = new ethers.Contract(
      USDCBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    );
    const USDCLocker = new ethers.Contract(
      USDCStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );
    await USDCBPool.approve(USDCStakeLockerAddress, "100000000000000000000");
    await USDCLocker.stake("100000000000000000000");
  });

  it("Can finalize USDC pool with stake", async function () {
    await USDCLP.finalize();
    isfin = await USDCLP.isFinalized();
    expect(isfin.toString()).to.equal("true");
  });

  //keep these two at bottom or do multiple times
  it("DAI BPT bal of stakeLocker is same as stakeLocker total token supply", async function () {
    DAIStakeLockerAddress = DAILP.stakeLockerAddress();
    const DAILocker = new ethers.Contract(
      DAIStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    );
    const totalsup = await DAILocker.totalSupply();
    const BPTbal = await DAIBPool.balanceOf(DAIStakeLockerAddress);
    expect(BPTbal).to.equal(totalsup);
  });

  it("USDC BPT bal of stakeLocker is same as stakeLocker total token supply", async function () {
    USDCStakeLockerAddress = USDCLP.stakeLockerAddress();
    const USDCLocker = new ethers.Contract(
      USDCStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );
    const USDCBPool = new ethers.Contract(
      USDCBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    );
    const totalsup = await USDCLocker.totalSupply();
    const BPTbal = await USDCBPool.balanceOf(USDCStakeLockerAddress);
    expect(BPTbal).to.equal(totalsup);
  });

  it("DAI LiquidityLocker created, known to factory and LP?", async function () {
    const DAILockerLP = await DAILP.liquidityLockerAddress();
    const DAIisLock = await LALockerFactory.isLiquidityLocker(DAILockerLP);
    expect(DAIisLock).to.equal(true);
  });

  it("USDC LiquidityLocker created, known to factory and LP?", async function () {
    const USDCLockerLP = await USDCLP.liquidityLockerAddress();
    const USDCisLock = await LALockerFactory.isLiquidityLocker(USDCLockerLP);
    expect(USDCisLock).to.equal(true);
  });

  it("Mapping DAI locker to parent pool", async function () {
    const DAILockerAddress = await DAILP.liquidityLockerAddress();
    const DAIPool = await LALockerFactory.getOwner(DAILockerAddress);
    expect(DAIPool).to.equal(DAILPAddress);
  });

  it("Mapping USDC locker to parent pool", async function () {
    const USDCLockerAddress = await USDCLP.liquidityLockerAddress();
    const USDCPool = await LALockerFactory.getOwner(USDCLockerAddress);
    expect(USDCPool).to.equal(USDCLPAddress);
  });

  it("Check DAI LP is recognized by LPFactory.isLPool()", async function () {
    const isPool = await LPFactory.isLPool(DAILPAddress);
    expect(isPool).to.equal(true);
  });

  it("Check USDC LP is recognized by LPFactory.isLPool()", async function () {
    const isPool = await LPFactory.isLPool(USDCLPAddress);
    expect(isPool).to.equal(true);
  });

  it("Random guy can not USDC Liquid Asset Locker Spend", async function () {
    const USDCLockerAddress = await USDCLP.liquidityLockerAddress();
    const USDCLALocker = new ethers.Contract(
      USDCLockerAddress,
      LiquidityLockerABI,
      ethers.provider.getSigner(0)
    );
    await expect(USDCLALocker.transfer(accounts[0], 0)).to.be.revertedWith(
      "LiquidityLocker:ERR_MSG_SENDER_NOT_OWNER"
    );
  });

  it("Random guy can not DAI Liquid Asset Locker Spend", async function () {
    const DAILockerAddress = await DAILP.liquidityLockerAddress();
    const DAILALocker = new ethers.Contract(
      DAILockerAddress,
      LiquidityLockerABI,
      ethers.provider.getSigner(0)
    );
    await expect(DAILALocker.transfer(accounts[0], 0)).to.be.revertedWith(
      "LiquidityLocker:ERR_MSG_SENDER_NOT_OWNER"
    );
  });

  it("DEPOSIT INTO USDC LP WITHOUT allowance, revert", async function () {
    const money = 100;
    const dec = BigInt(await USDC.decimals());
    const moneyUSDC = BigInt(money) * BigInt(10) ** dec;
    const moneyInWEI = BigInt(money) * BigInt(10) ** BigInt(18);
    expect(USDCLP.deposit(moneyUSDC)).to.revertedWith(
      "LiquidityPool::deposit:ERR_ALLOWANCE_LESS_THEN__AMT"
    );
  });

  it("DEPOSIT INTO DAI LP WITHOUT allowance, revert", async function () {
    const money = 100;
    const dec = BigInt(await DAI.decimals());
    const moneyDAI = BigInt(money) * BigInt(10) ** dec;
    const moneyInWEI = BigInt(money) * BigInt(10) ** BigInt(18);
    expect(DAILP.deposit(moneyDAI)).to.revertedWith(
      "LiquidityPool::deposit:ERR_ALLOWANCE_LESS_THEN__AMT"
    );
  });

  it("DEPOSIT INTO USDC LP, Check if depositor is issued appropriate balance of FDT", async function () {
    const money = 100;
    const dec = BigInt(await USDC.decimals());
    const moneyUSDC = BigInt(money) * BigInt(10) ** dec;
    const moneyInWEI = BigInt(money) * BigInt(10) ** BigInt(18);
    await USDC.approve(USDCLP.address, moneyUSDC);
    await USDCLP.deposit(moneyUSDC);
    const USDCFDTbal = BigInt(await USDCLP.balanceOf(accounts[0]));
    expect(USDCFDTbal.toString()).to.equal(moneyInWEI.toString());
  });

  it("DEPOSIT INTO DAI LP, Check if depositor is issued appropriate balance of FDT", async function () {
    const money = 100;
    const dec = BigInt(await DAI.decimals());
    const moneyDAI = BigInt(money) * BigInt(10) ** dec;
    const moneyInWEI = BigInt(money) * BigInt(10) ** BigInt(18);
    await DAI.approve(DAILP.address, moneyDAI);
    await DAILP.deposit(moneyDAI);
    const DAIFDTbal = BigInt(await DAILP.balanceOf(accounts[0]));
    expect(DAIFDTbal.toString()).to.equal(moneyInWEI.toString());
  });

  it("Customer/third party stake some DAI", async function () {
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(5)
    );
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(5)
    );
    DAIacct5 = new ethers.Contract(
      DAIAddress,
      DAIABI,
      ethers.provider.getSigner(5)
    );
    usdstake = BigInt(1000);
    DAIstake = BigInt(10 ** 18) * usdstake;
    await DAI.transfer(accounts[5], DAIstake);
    await DAIacct5.approve(DAIBPoolAddress, DAIstake);
    await DAIBPool.joinswapExternAmountIn(DAIAddress, DAIstake, 0);
    bptbal = BigInt(await DAIBPool.balanceOf(accounts[5]));
    await DAIBPool.approve(DAIStakeLockerAddress, bptbal);
    await DAIStakeLocker.stake(bptbal);
    fdtbal = await DAIStakeLocker.balanceOf(accounts[5]);
    expect(fdtbal.toString()).to.equal(bptbal.toString());
  });

  it("third party CANT unstake with unsatisfied unstakeDelay?", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(5)
    );
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(5)
    );
    await MPLGlobals.setUnstakeDelay("999999999999999999");
    fdtbal = BigInt(await DAIStakeLocker.balanceOf(accounts[5]));
    bptbal1 = BigInt(await DAIBPool.balanceOf(accounts[5]));
    await expect(DAIStakeLocker.unstake(fdtbal)).to.be.revertedWith(
      "LPStakelocker: not enough unstakeable balance"
    );

    fdtbal2 = BigInt(await DAIStakeLocker.balanceOf(accounts[5]));
    bptbal2 = BigInt(await DAIBPool.balanceOf(accounts[5]));
    bptbaldiff = bptbal2 - bptbal1;
    expect(bptbaldiff.toString()).to.equal("0");
    expect(fdtbal2.toString()).to.equal(fdtbal.toString());
    await MPLGlobals.setUnstakeDelay("0");
  });

  it("can third party unstake with zero unstakeDelay?, did he get his BPTs back?", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(5)
    );
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(5)
    );
    fdtbal = BigInt(await DAIStakeLocker.balanceOf(accounts[5]));
    bptbal1 = BigInt(await DAIBPool.balanceOf(accounts[5]));
    await DAIStakeLocker.unstake(fdtbal);
    bptbal2 = BigInt(await DAIBPool.balanceOf(accounts[5]));
    bptbaldiff = bptbal2 - bptbal1;
    fdtbal2 = BigInt(await DAIStakeLocker.balanceOf(accounts[5]));
    expect(bptbaldiff.toString()).to.equal(fdtbal.toString());
    expect(fdtbal2.toString()).to.equal("0");
  });

  it("check isDefunct() DAI LP", async function () {
    defunct = await DAILP.isDefunct();
    expect(defunct).to.equal(false);
  });

  it("delegate can not unstake", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );
    await expect(DAIStakeLocker.unstake(100)).to.be.revertedWith(
      "LPStakeLocker:ERR DELEGATE STAKE LOCKED"
    );
  });

  it("delegate can not transfer FDTs", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(0)
    );
    await expect(DAIStakeLocker.transfer(accounts[2], 100)).to.be.revertedWith(
      "LPStakeLocker:ERR DELEGATE STAKE LOCKED"
    );
  });

  it("Check partial unstake ability.", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(5)
    );
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(5)
    );
    const stakeDelay = 10;
    await MPLGlobals.setUnstakeDelay(stakeDelay);

    bptbal = BigInt(await DAIBPool.balanceOf(accounts[5]));
    await DAIBPool.approve(DAIStakeLockerAddress, bptbal);
    await DAIStakeLocker.stake(bptbal);
    await new Promise((r) => setTimeout(r, 2000));
    await MPLGlobals.setUnstakeDelay(stakeDelay); //generic tx to issue a new block so next view can see it
    const ubal = await DAIStakeLocker.getUnstakeableBalance(accounts[5]);
    const bal = await DAIStakeLocker.balanceOf(accounts[5]);
    // this is because the denominator has a +1 to prevent div by 0
    // double precision arithmatic truncation error means we will get inaccuracy after about 15 digits
    expect(Math.abs(ubal / bal - 2 / (stakeDelay + 1)) < 10 ** -15);
  });

  it("Check FDT capability in DAI stake locker", async function () {
    //DUPLICATE SOME OF THESE DAI LOCKER TESTS TO RUN ON USDC TOOOO!!
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(5)
    );
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(5)
    );
    bptbal = BigInt(await DAIBPool.balanceOf(accounts[5]));
    await DAIBPool.approve(DAIStakeLockerAddress, bptbal);
    await DAIStakeLocker.stake(bptbal);
    DAIReward = BigInt(10000) * BigInt(10 ** 18);
    await DAI.transfer(DAIStakeLockerAddress, DAIReward);
    await DAIStakeLocker.updateFundsReceived();
    DAIbal0 = BigInt(await DAI.balanceOf(accounts[5]));
    await DAIStakeLocker.withdrawFunds();
    DAIbal1 = BigInt(await DAI.balanceOf(accounts[5]));
    baldiff = DAIbal1 - DAIbal0;
    FDTbal = await DAIStakeLocker.balanceOf(accounts[5]);
    totalFDT = await DAIStakeLocker.totalSupply();
    ratio = BigNumber(FDTbal / totalFDT);
    expectedDAI = BigNumber(ratio * BigNumber(DAIReward));
    //the expected dai is off due to roundoff. i must not be using bignumber correctly here
    expect(expectedDAI / BigNumber(baldiff)).to.equal(1);
  });

  it("Check that random people can not call admin commands on stake lockers", async function () {
    const USDCStakeLocker = new ethers.Contract(
      USDCStakeLockerAddress,
      StakeLockerABI,
      ethers.provider.getSigner(2)
    );
    //MAYBE FIGURE OUT WHY THIS WAS HAVING MYSTERIOUS PROBLEMS
    await expect(USDCStakeLocker.deleteLP()).to.be.revertedWith(
      "LPStakeLocker:ERR UNAUTHORIZED"
    );
    await expect(USDCStakeLocker.finalizeLP()).to.be.revertedWith(
      "LPStakeLocker:ERR UNAUTHORIZED"
    );
  });

  it("Execute fundloan()", async function () {
    LVF = new ethers.Contract(
      LVFactoryAddress,
      LVFactoryABI,
      ethers.provider.getSigner(0)
    );
    const LV1 = await LVF.getLoanVault(0);
    await DAILP.fundLoan(LV1, 100);
  });

  it("check if you can execute fundLoan on a random address", async function () {
    await expect(DAILP.fundLoan(accounts[1], 100)).to.be.revertedWith(
      "LiquidityPool::fundLoan:ERR_LOAN_VAULT_INVALID"
    );
  });

});
