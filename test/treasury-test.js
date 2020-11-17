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
<<<<<<< HEAD
const WBTCAddress = require('../../contracts/src/contracts/WBTC.address.js')
const WBTCABI = require('../../contracts/src/contracts/WBTC.abi.js')
=======
const uniswapV2PairABI = require('../../contracts/src/contracts/UniswapV2Pair.abi.js')
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7


describe('MapleTreasury.sol', function () {

  let mintableDAI, fundsToken, mapleTreasury, mapleToken, uniswapRouter, uniswapFactory;

  before(async () => {
    mintableDAI = new ethers.Contract(mintableDAIAddress, mintableDAIABI, ethers.provider.getSigner(0))
    fundsToken = new ethers.Contract(fundsTokenAddress, fundsTokenABI, ethers.provider.getSigner(0))
    mapleTreasury = new ethers.Contract(treasuryAddress, treasuryABI, ethers.provider.getSigner(0))
    mapleToken = new ethers.Contract(mapleTokenAddress, mapleTokenABI, ethers.provider.getSigner(0))
    uniswapRouter = new ethers.Contract(uniswapRouterAddress, uniswapRouterABI,ethers.provider.getSigner(0))
    uniswapFactory = new ethers.Contract(uniswapFactoryAddress, uniswapFactoryABI, ethers.provider.getSigner(0))
<<<<<<< HEAD
    wBTC = new ethers.Contract(WBTCAddress, WBTCABI, ethers.provider.getSigner(0))
=======
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
  })

  it('mint DAI and fundsToken (USDC) within MapleTreasury', async function () {
    // mintSpecial() takes in whole number (i.e. 100) and mints (100 * 10**decimals)
    expect(await mintableDAI.mintSpecial(treasuryAddress, 1000))
    expect(await fundsToken.mintSpecial(treasuryAddress, 1000))
  })

  it('pass through USDC to MapleToken', async function () {
    
    const fundsTokenDecimals = await fundsToken.decimals()
    const treasuryBalancePre = BigInt(await fundsToken.balanceOf(treasuryAddress));
    const MPLBalancePre = BigInt(await fundsToken.balanceOf(mapleTokenAddress));
    
    expect(await mapleTreasury.passThroughFundsToken())
<<<<<<< HEAD
=======
    
    const treasuryBalancePost = BigInt(await fundsToken.balanceOf(treasuryAddress));
    const MPLBalancePost = BigInt(await fundsToken.balanceOf(mapleTokenAddress));

    expect(Number(treasuryBalancePre - treasuryBalancePost)).to.equals(1000 * 10 ** fundsTokenDecimals)
    expect(Number(MPLBalancePost - MPLBalancePre)).to.equals(1000 * 10 ** fundsTokenDecimals)
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7

  })

  it('ensure uniswapRouter is pointing to unsiwapFactory', async function() {
    const factoryAddress = await uniswapRouter.factory()
    expect(factoryAddress).to.equals(uniswapFactoryAddress)
  })

  it('add liquidity to DAI/USDC pool', async function () {
    
    const accounts = await ethers.provider.listAccounts()
    const DAIDecimals = await mintableDAI.decimals()
    const USDCDecimals = await fundsToken.decimals()
<<<<<<< HEAD

    expect(await mintableDAI.mintSpecial(accounts[0], 100000))
    expect(await fundsToken.mintSpecial(accounts[0], 100000))

=======
    expect(await mintableDAI.mintSpecial(accounts[0], 100000))
    expect(await fundsToken.mintSpecial(accounts[0], 100000))
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
    expect(await mintableDAI.approve(uniswapRouterAddress, BigInt(100000 * 10**DAIDecimals)))
    expect(await fundsToken.approve(uniswapRouterAddress, BigInt(100000 * 10**USDCDecimals)))

    const test = await uniswapRouter.addLiquidity(
      mintableDAIAddress,
      fundsTokenAddress,
      BigInt(100000 * 10**DAIDecimals),
      BigInt(100000 * 10**USDCDecimals),
      0,
      0,
      accounts[0],
      Math.floor(Date.now() / 1000) + 1000
    )

  })

<<<<<<< HEAD
  it('convert DAI to USDC via convertERC20()', async function () {
=======
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
    expect(getPairDAIBalance).is.greaterThan(10000);
    expect(getPairUSDCBalance).is.greaterThan(10000);

  })


  it('convert DAI to USDC via bilateral swap', async function () {
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7
    
    const DAIDecimals = await mintableDAI.decimals()
    const USDCDecimals = await fundsToken.decimals()
    let treasuryDAIBalance = await mintableDAI.balanceOf(treasuryAddress)
    let mapleUSDCBalance = await fundsToken.balanceOf(mapleTokenAddress)
    treasuryDAIBalance = parseInt(treasuryDAIBalance["_hex"]) / 10**DAIDecimals
    mapleUSDCBalance = parseInt(mapleUSDCBalance["_hex"]) / 10**USDCDecimals

<<<<<<< HEAD
    expect(await mapleTreasury.convertERC20(mintableDAIAddress))
=======
    console.log(treasuryDAIBalance)
    console.log(mapleUSDCBalance)
    
    expect(await mapleTreasury.convertERC20Bilateral(mintableDAIAddress))
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7

    treasuryDAIBalance = await mintableDAI.balanceOf(treasuryAddress)
    mapleUSDCBalance = await fundsToken.balanceOf(mapleTokenAddress)
    treasuryDAIBalance = parseInt(treasuryDAIBalance["_hex"]) / 10**DAIDecimals
    mapleUSDCBalance = parseInt(mapleUSDCBalance["_hex"]) / 10**USDCDecimals

<<<<<<< HEAD
  })

  it('send ETH to mapleTreasury, convert via convertETH()', async function () {
    
    // const tx = await ethers.provider.getSigner(0).sendTransaction({
    //   to: treasuryAddress,
    //   value: ethers.utils.parseEther("1.0")
    // });
    
    let WETHADD = await uniswapRouter.WETH();
    console.log(WETHADD);

    let preBalance = BigInt(await ethers.provider.getBalance(treasuryAddress))
    console.log(preBalance)

    expect(await mapleTreasury.convertETH('1000000000000'));

    let postBalance = BigInt(await ethers.provider.getBalance(treasuryAddress))
    console.log(postBalance)
=======
    console.log(treasuryDAIBalance)
    console.log(mapleUSDCBalance)
>>>>>>> 4803460a07d87723973ecc20de74ab40d6fc3ee7

  })

})
