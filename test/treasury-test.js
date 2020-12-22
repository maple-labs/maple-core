const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const artpath = '../../src/' + network.name + '/';


const mintableDAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
const mintableDAIABI = require(artpath + "abis/MintableTokenDAI.abi.js");
const treasuryAddress = require(artpath + "addresses/MapleTreasury.address.js");
const treasuryABI = require(artpath + "abis/MapleTreasury.abi.js");
const fundsTokenAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");
const fundsTokenABI = require(artpath + "abis/MintableTokenUSDC.abi.js");
const mapleTokenAddress = require(artpath + "addresses/MapleToken.address.js");
const mapleTokenABI = require(artpath + "abis/MapleToken.abi.js");
const uniswapRouterAddress = require(artpath + "addresses/UniswapV2Router02.address");
const uniswapRouterABI = require(artpath + "abis/UniswapV2Router02.abi");
const uniswapFactoryAddress = require(artpath + "addresses/UniswapV2Factory.address.js");
const uniswapFactoryABI = require(artpath + "abis/UniswapV2Factory.abi.js");
const WBTCAddress = require(artpath + "addresses/WBTC.address.js");
const WBTCABI = require(artpath + "abis/WBTC.abi.js");

describe("MapleTreasury.sol", function () {
  let mintableDAI,
    fundsToken,
    mapleTreasury,
    mapleToken,
    uniswapRouter,
    uniswapFactory;

  before(async () => {
    mintableDAI = new ethers.Contract(
      mintableDAIAddress,
      mintableDAIABI,
      ethers.provider.getSigner(0)
    );
    fundsToken = new ethers.Contract(
      fundsTokenAddress,
      fundsTokenABI,
      ethers.provider.getSigner(0)
    );
    mapleTreasury = new ethers.Contract(
      treasuryAddress,
      treasuryABI,
      ethers.provider.getSigner(0)
    );
    mapleToken = new ethers.Contract(
      mapleTokenAddress,
      mapleTokenABI,
      ethers.provider.getSigner(0)
    );
    uniswapRouter = new ethers.Contract(
      uniswapRouterAddress,
      uniswapRouterABI,
      ethers.provider.getSigner(0)
    );
    uniswapFactory = new ethers.Contract(
      uniswapFactoryAddress,
      uniswapFactoryABI,
      ethers.provider.getSigner(0)
    );
    wBTC = new ethers.Contract(
      WBTCAddress,
      WBTCABI,
      ethers.provider.getSigner(0)
    );
  });

  it("mint DAI and fundsToken (USDC) within MapleTreasury", async function () {
    // mintSpecial() takes in whole number (i.e. 100) and mints (100 * 10**decimals)
    expect(await mintableDAI.mintSpecial(treasuryAddress, 1000));
    expect(await fundsToken.mintSpecial(treasuryAddress, 1000));
  });

  it("pass through USDC to MapleToken", async function () {
    const fundsTokenDecimals = await fundsToken.decimals();
    const treasuryBalancePre = BigInt(
      await fundsToken.balanceOf(treasuryAddress)
    );
    const MPLBalancePre = BigInt(await fundsToken.balanceOf(mapleTokenAddress));

    expect(await mapleTreasury.passThroughFundsToken());
  });

  it("ensure uniswapRouter is pointing to unsiwapFactory", async function () {
    const factoryAddress = await uniswapRouter.factory();
    expect(factoryAddress).to.equals(uniswapFactoryAddress);
  });

  it("add liquidity to DAI/USDC pool", async function () {
    const accounts = await ethers.provider.listAccounts();
    const DAIDecimals = await mintableDAI.decimals();
    const USDCDecimals = await fundsToken.decimals();

    expect(await mintableDAI.mintSpecial(accounts[0], 100000));
    expect(await fundsToken.mintSpecial(accounts[0], 100000));

    expect(
      await mintableDAI.approve(
        uniswapRouterAddress,
        BigInt(100000 * 10 ** DAIDecimals)
      )
    );
    expect(
      await fundsToken.approve(
        uniswapRouterAddress,
        BigInt(100000 * 10 ** USDCDecimals)
      )
    );

    const test = await uniswapRouter.addLiquidity(
      mintableDAIAddress,
      fundsTokenAddress,
      BigInt(100000 * 10 ** DAIDecimals),
      BigInt(100000 * 10 ** USDCDecimals),
      0,
      0,
      accounts[0],
      "999999999999999999"
    );
  });

  it("ensure uniswapRouter is pointing to unsiwapFactory", async function () {
    const factoryAddress = await uniswapRouter.factory();
    expect(factoryAddress).to.equals(uniswapFactoryAddress);
  });

  it("convert DAI to USDC via convertERC20()", async function () {
    const DAIDecimals = await mintableDAI.decimals();
    const USDCDecimals = await fundsToken.decimals();
    let treasuryDAIBalance = await mintableDAI.balanceOf(treasuryAddress);
    let mapleUSDCBalance = await fundsToken.balanceOf(mapleTokenAddress);
    treasuryDAIBalance =
      parseInt(treasuryDAIBalance["_hex"]) / 10 ** DAIDecimals;
    mapleUSDCBalance = parseInt(mapleUSDCBalance["_hex"]) / 10 ** USDCDecimals;

    expect(await mapleTreasury.convertERC20(mintableDAIAddress));

    treasuryDAIBalance = await mintableDAI.balanceOf(treasuryAddress);
    mapleUSDCBalance = await fundsToken.balanceOf(mapleTokenAddress);
    treasuryDAIBalance =
      parseInt(treasuryDAIBalance["_hex"]) / 10 ** DAIDecimals;
    mapleUSDCBalance = parseInt(mapleUSDCBalance["_hex"]) / 10 ** USDCDecimals;
  });

  it("claim fee distribution from convertERC20()", async function () {
    const accounts = await ethers.provider.listAccounts();
    const preWithdraw = await mapleToken.withdrawnFundsOf(accounts[0]);

    expect(await mapleToken.withdrawFunds());

    const postWithdraw = await mapleToken.withdrawnFundsOf(accounts[0]);

    expect(parseInt(postWithdraw["_hex"])).to.be.above(
      parseInt(preWithdraw["_hex"])
    );
  });

  it("send ETH to mapleTreasury, convert via convertETH()", async function () {
    const tx = await ethers.provider.getSigner(0).sendTransaction({
      to: treasuryAddress,
      value: ethers.utils.parseEther("1.0"),
    });

    let ETHBalance = BigInt(await ethers.provider.getBalance(treasuryAddress));
    expect(await mapleTreasury.convertETH("10000000", ETHBalance));
  });

  it("claim fee distribution from convertETH()", async function () {
    const accounts = await ethers.provider.listAccounts();
    const preWithdraw = await mapleToken.withdrawnFundsOf(accounts[0]);

    expect(await mapleToken.withdrawFunds());

    const postWithdraw = await mapleToken.withdrawnFundsOf(accounts[0]);

    expect(parseInt(postWithdraw["_hex"])).to.be.above(
      parseInt(preWithdraw["_hex"])
    );
  });
});
