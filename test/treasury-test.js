const { expect, assert } = require('chai')
const { BigNumber } = require('ethers')

const mintableDAIAddress = require('../../contracts/src/contracts/MintableTokenDAI.address.js')
const mintableDAIABI = require('../../contracts/src/contracts/MintableTokenDAI.abi.js')
const treasuryAddress = require('../../contracts/src/contracts/MapleTreasury.address.js')
const treasuryABI = require('../../contracts/src/contracts/MapleTreasury.abi.js')
const fundsTokenAddress = require('../../contracts/src/contracts/MintableTokenUSDC.address.js')
const fundsTokenABI = require('../../contracts/src/contracts/MintableTokenUSDC.abi.js')
const mapleTokenAddress = require('../../contracts/src/contracts/MapleToken.address.js')
const mapleTokenABI = require('../../contracts/src/contracts/MapleToken.abi.js')
const uniswapRouterAddress = require('../../contracts/src/contracts/UniswapV2Router02.address.js')
const uniswapRouterABI = require('../../contracts/src/contracts/UniswapV2Router02.abi.js')
const uniswapFactoryAddress = require('../../contracts/src/contracts/UniswapV2Factory.address.js')
const uniswapFactoryABI = require('../../contracts/src/contracts/UniswapV2Factory.abi.js')
const uniswapV2PairABI = require('../../contracts/src/contracts/UniswapV2Pair.abi.js')


describe('MapleTreasury.sol', function () {

  let mintableDAI, fundsToken, mapleTreasury, mapleToken, uniswapRouter, uniswapFactory;

  before(async () => {
    mintableDAI = new ethers.Contract(
      mintableDAIAddress, 
      mintableDAIABI, 
      ethers.provider.getSigner(0)
    )
    fundsToken = new ethers.Contract(
      fundsTokenAddress, 
      fundsTokenABI, 
      ethers.provider.getSigner(0)
    )
    mapleTreasury = new ethers.Contract(
      treasuryAddress, 
      treasuryABI, 
      ethers.provider.getSigner(0)
    )
    mapleToken = new ethers.Contract(
      mapleTokenAddress, 
      mapleTokenABI, 
      ethers.provider.getSigner(0)
    )
    uniswapRouter = new ethers.Contract(
      uniswapRouterAddress, 
      uniswapRouterABI, 
      ethers.provider.getSigner(0)
    )
    uniswapFactory = new ethers.Contract(
      uniswapFactoryAddress, 
      uniswapFactoryABI, 
      ethers.provider.getSigner(0)
    )
  })

  it('mint DAI and fundsToken (USDC) within MapleTreasury', async function () {
    
    // mintSpecial() takes in whole number (i.e. 100) and mints (100 * 10**decimals)
    expect(await mintableDAI.mintSpecial(treasuryAddress, 10))
    expect(await fundsToken.mintSpecial(treasuryAddress, 10))

  })

  it('pass through USDC to MapleToken', async function () {
    
    const fundsTokenDecimals = await fundsToken.decimals()
    const treasuryBalancePre = BigInt(await fundsToken.balanceOf(treasuryAddress));
    const MPLBalancePre = BigInt(await fundsToken.balanceOf(mapleTokenAddress));
    
    expect(await mapleTreasury.passThroughFundsToken())
    
    const treasuryBalancePost = BigInt(await fundsToken.balanceOf(treasuryAddress));
    const MPLBalancePost = BigInt(await fundsToken.balanceOf(mapleTokenAddress));

    expect(Number(treasuryBalancePre - treasuryBalancePost)).to.equals(10 * 10 ** fundsTokenDecimals)
    expect(Number(MPLBalancePost - MPLBalancePre)).to.equals(10 * 10 ** fundsTokenDecimals)

  })

  it('get uniswap pool basic information', async function () {

    const getPairAddress = await uniswapFactory.getPair(mintableDAIAddress, fundsTokenAddress);
    const getPairAddressAgain = await uniswapFactory.getPair(fundsTokenAddress, mintableDAIAddress);

    expect(getPairAddress).to.equals(getPairAddressAgain);

    uniswapPair = new ethers.Contract(
      getPairAddressAgain, 
      uniswapV2PairABI, 
      ethers.provider.getSigner(0)
    )

    const pairName = await uniswapPair.name();
    const pairSymbol = await uniswapPair.symbol();
    const pairDecimals = await uniswapPair.decimals();
    const pairTotalSupply = await uniswapPair.totalSupply();

    const DAIDecimals = await mintableDAI.decimals()
    const USDCDecimals = await fundsToken.decimals()
    let getPairDAIBalance = await mintableDAI.balanceOf(getPairAddressAgain)
    let getPairUSDCBalance = await fundsToken.balanceOf(getPairAddressAgain)
    getPairDAIBalance = parseInt(getPairDAIBalance["_hex"]) / 10**DAIDecimals
    getPairUSDCBalance = parseInt(getPairUSDCBalance["_hex"]) / 10**USDCDecimals
    
    expect(pairName).to.equals("Uniswap V2");
    expect(pairSymbol).to.equals("UNI-V2");
    expect(pairDecimals).to.equals(18);
    expect(getPairDAIBalance).to.equals(10000);
    expect(getPairUSDCBalance).to.equals(10000);

    const factoryAddress = await uniswapRouter.factory()
    
    expect(factoryAddress).to.equals()

  })

  it('attempt via personal wallet, convert DAI to USDC', async function () {
  
    const accounts = await ethers.provider.listAccounts()
    const DAIDecimals = await mintableDAI.decimals()
    let personalDAIBalance = await mintableDAI.balanceOf(accounts[0])
    personalDAIBalance = parseInt(personalDAIBalance["_hex"]) / 10**DAIDecimals

    const amountToApproveTransfer = BigInt(10 * 10**DAIDecimals)
    expect(await mintableDAI.approve(uniswapRouterAddress, amountToApproveTransfer))

    expect(await uniswapRouter.swapExactTokensForTokens(
      amountToApproveTransfer,
      0,
      [mintableDAIAddress, fundsTokenAddress],
      accounts[0],
      Math.floor(Date.now() / 1000) + 1000
    ))
    
    personalDAIBalance = await mintableDAI.balanceOf(accounts[0])
    personalDAIBalance = parseInt(personalDAIBalance["_hex"]) / 10**DAIDecimals

  })

  it('convert DAI to USDC via bilateral swap', async function () {
    
    const DAIDecimals = await mintableDAI.decimals()
    let treasuryDAIBalance = await mintableDAI.balanceOf(treasuryAddress)
    treasuryDAIBalance = parseInt(treasuryDAIBalance["_hex"]) / 10**DAIDecimals

    console.log(treasuryDAIBalance)
    
    expect(await mapleTreasury.convertERC20Bilateral(mintableDAIAddress))

  })

})
