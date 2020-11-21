const { expect } = require("chai");
const DAIAddress = require("../../contracts/localhost/addresses/MintableTokenDAI.address.js");
const DAIAbi = require("../../contracts/localhost/abis/MintableTokenDAI.abi.js");
const BPoolABI = require("../../contracts/localhost/abis/BPool.abi.js");
const stakeLockerABI = require("../../contracts/localhost/abis/LPStakeLocker.abi.js");
const LPABI = require("../../contracts/localhost/abis/LiquidityPool.abi.js");
const USDCAddress = require("../../contracts/localhost/addresses/MintableTokenUSDC.address.js");
const USDCAbi = require("../../contracts/localhost/abis/MintableTokenUSDC.abi.js");

const bcAddress = require("../../contracts/localhost/addresses/BCreator.address.js");
const bcABI = require("../../contracts/localhost/abis/BCreator.abi.js");
const mplAddress = require("../../contracts/localhost/addresses/MapleToken.address.js");
const mplABI = require("../../contracts/localhost/abis/MapleToken.abi.js");
const MPLGlobalsAddress = require("../../contracts/localhost/addresses/MapleGlobals.address.js");
const LPLockerFactoryABI = require("../../contracts/localhost/abis/LPStakeLockerFactory.abi.js");
const LPFactoryABI = require("../../contracts/localhost/abis/LPFactory.abi.js");
const LPLockerFactoryAddress = require("../../contracts/localhost/addresses/LPStakeLockerFactory.address.js");
const LPFactoryAddress = require("../../contracts/localhost/addresses/LPFactory.address.js");
const liquidLockerABI = require("../../contracts/localhost/abis/LiquidAssetLocker.abi.js");
const liquidLockerFactoryABI = require("../../contracts/localhost/abis/LiquidAssetLockerFactory.abi.js");
const liquidLockerFactoryAddress = require("../../contracts/localhost/addresses/LiquidAssetLockerFactory.address.js");

describe("Liquidity Pool and respective lockers", function () {
  let DAILP;
  let USDCLP;
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
    LPLockerFactory = new ethers.Contract(
      LPLockerFactoryAddress,
      LPLockerFactoryABI,
      ethers.provider.getSigner(0)
    );
    const bc = new ethers.Contract(
      bcAddress,
      bcABI,
      ethers.provider.getSigner(0)
    );
    USDC = new ethers.Contract(
      USDCAddress,
      USDCAbi,
      ethers.provider.getSigner(0)
    );

    DAI = new ethers.Contract(DAIAddress, DAIAbi, ethers.provider.getSigner(0));

    DAIBPoolAddress = await bc.getBPoolAddress(0);
    USDCBPoolAddress = await bc.getBPoolAddress(1);
    await LPFactory.createLiquidityPool(
      DAIAddress,
      DAIBPoolAddress,
      LPLockerFactoryAddress,
      liquidLockerFactoryAddress,
      "Maple DAI LP",
      "LPDAI",
      MPLGlobalsAddress
    );
    await LPFactory.createLiquidityPool(
      USDCAddress,
      USDCBPoolAddress,
      LPLockerFactoryAddress,
      liquidLockerFactoryAddress,
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
      liquidLockerFactoryAddress,
      liquidLockerFactoryABI,
      ethers.provider.getSigner(0)
    );
    DAIStakeLockerAddress = await DAILP.stakedAssetLocker();
    USDCStakeLockerAddress = await USDCLP.stakedAssetLocker();
  });
  it("Sets the correct owners for Token Lockers", async function () {
    const DAILockerowner = await LPLockerFactory.getPool(DAIStakeLockerAddress);
    const USDCLockerowner = await LPLockerFactory.getPool(
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
      stakeLockerABI,
      ethers.provider.getSigner(0)
    );
    await DAIBPool.approve(DAIStakeLockerAddress, "100000000000000000000");
    await DAILocker.stake("100000000000000000000");
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
      stakeLockerABI,
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
  it("DAI BPT bal of stakedAssetLocker is same as stakedAssetLocker total token supply", async function () {
    DAIStakeLockerAddress = DAILP.stakedAssetLocker();
    const DAILocker = new ethers.Contract(
      DAIStakeLockerAddress,
      stakeLockerABI,
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

  it("USDC BPT bal of stakedAssetLocker is same as stakedAssetLocker total token supply", async function () {
    USDCStakeLockerAddress = USDCLP.stakedAssetLocker();
    const USDCLocker = new ethers.Contract(
      USDCStakeLockerAddress,
      stakeLockerABI,
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
  it("DAI LiquidAssetLocker created, known to factory and LP?", async function () {
    const DAILockerLP = await DAILP.LiquidAssetLocker();
    const DAIisLock = await LALockerFactory.isLiquidAssetLocker(DAILockerLP);
    expect(DAIisLock).to.equal(true);
  });

  it("USDC LiquidAssetLocker created, known to factory and LP?", async function () {
    const USDCLockerLP = await USDCLP.LiquidAssetLocker();
    const USDCisLock = await LALockerFactory.isLiquidAssetLocker(USDCLockerLP);
    expect(USDCisLock).to.equal(true);
  });
  it("Mapping DAI locker to parent pool", async function () {
    const DAILockerAddress = await DAILP.LiquidAssetLocker();
    const DAIPool = await LALockerFactory.getPool(DAILockerAddress);
    expect(DAIPool).to.equal(DAILPAddress);
  });
  it("Mapping USDC locker to parent pool", async function () {
    const USDCLockerAddress = await USDCLP.LiquidAssetLocker();
    const USDCPool = await LALockerFactory.getPool(USDCLockerAddress);
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
    const USDCLockerAddress = await USDCLP.LiquidAssetLocker();
    const USDCLALocker = new ethers.Contract(
      USDCLockerAddress,
      liquidLockerABI,
      ethers.provider.getSigner(0)
    );
    await expect(USDCLALocker.transfer(accounts[0], 0)).to.be.revertedWith(
      "ERR:LiquidAssetLocker: IS NOT OWNER POOL"
    );
  });
  it("Random guy can not DAI Liquid Asset Locker Spend", async function () {
    const DAILockerAddress = await DAILP.LiquidAssetLocker();
    const DAILALocker = new ethers.Contract(
      DAILockerAddress,
      liquidLockerABI,
      ethers.provider.getSigner(0)
    );
    await expect(DAILALocker.transfer(accounts[0], 0)).to.be.revertedWith(
      "ERR:LiquidAssetLocker: IS NOT OWNER POOL"
    );
  });
  it("DEPOSIT INTO USDC LP WITHOUT allowance, revert", async function () {
    const money = 100;
    const dec = BigInt(await USDC.decimals());
    const moneyUSDC = BigInt(money) * BigInt(10) ** dec;
    const moneyInWEI = BigInt(money) * BigInt(10) ** BigInt(18);
    expect(USDCLP.deposit(moneyUSDC)).to.revertedWith(
      "ERR:LP:cant transfer liquidasset"
    );
  });
  it("DEPOSIT INTO DAI LP WITHOUT allowance, revert", async function () {
    const money = 100;
    const dec = BigInt(await DAI.decimals());
    const moneyDAI = BigInt(money) * BigInt(10) ** dec;
    const moneyInWEI = BigInt(money) * BigInt(10) ** BigInt(18);
    expect(DAILP.deposit(moneyDAI)).to.revertedWith(
      "ERR:LP:cant transfer liquidasset"
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
      stakeLockerABI,
      ethers.provider.getSigner(5)
    );
    DAIacct5 = new ethers.Contract(
      DAIAddress,
      DAIAbi,
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
      stakeLockerABI,
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
      stakeLockerABI,
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
  it("delegate can not unstake", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      stakeLockerABI,
      ethers.provider.getSigner(0)
    );
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    );
    await expect(DAIStakeLocker.unstake(100)).to.be.revertedWith(
      "LPStakeLocker:ERR DELEGATE STAKE LOCKED"
    );
  });
  it("delegate can not transfer FDTs", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      stakeLockerABI,
      ethers.provider.getSigner(0)
    );
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    );
    await expect(DAIStakeLocker.transfer(accounts[2], 100)).to.be.revertedWith(
      "LPStakeLocker:ERR DELEGATE STAKE LOCKED"
    );
  });
  it("check unstakeable balance", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      stakeLockerABI,
      ethers.provider.getSigner(5)
    );
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(5)
    );
    await MPLGlobals.setUnstakeDelay("100");

    bptbal = BigInt(await DAIBPool.balanceOf(accounts[5]));
    await DAIBPool.approve(DAIStakeLockerAddress, bptbal);
    await DAIStakeLocker.stake(bptbal);
    await new Promise((r) => setTimeout(r, 2000));
  });
  it("check unstakeable balance", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      stakeLockerABI,
      ethers.provider.getSigner(5)
    );
    await MPLGlobals.setUnstakeDelay("100");

    const ubal = await DAIStakeLocker.getUnstakeableBalance(accounts[5]);
    console.log(ubal.toString());
  });
  it("Check FDT capability in DAI stake locker", async function () {
    const DAIStakeLocker = new ethers.Contract(
      DAIStakeLockerAddress,
      stakeLockerABI,
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
});
