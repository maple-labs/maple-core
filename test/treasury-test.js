const { expect, assert } = require('chai')

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
const { BigNumber } = require('ethers')

describe('MapleTreasury.sol', function () {

  let mintableDAI, fundsToken, mapleTreasury, mapleToken;

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
  })

  it('mint DAI and fundsToken (USDC) within MapleTreasury', async function () {
    
    // mintSpecial() takes in whole number (i.e. 100) and mints (100 * 10**decimals)
    expect(await mintableDAI.mintSpecial(treasuryAddress, 100))
    expect(await fundsToken.mintSpecial(treasuryAddress, 100))

  })

  it('pass through USDC to MapleToken', async function () {
    
    const fundsTokenDecimals = await fundsToken.decimals()
    const treasuryBalancePre = BigInt(await fundsToken.balanceOf(treasuryAddress));
    const MPLBalancePre = BigInt(await fundsToken.balanceOf(mapleTokenAddress));
    
    expect(await mapleTreasury.passThroughFundsToken())
    
    const treasuryBalancePost = BigInt(await fundsToken.balanceOf(treasuryAddress));
    const MPLBalancePost = BigInt(await fundsToken.balanceOf(mapleTokenAddress));

    expect(Number(treasuryBalancePre - treasuryBalancePost)).to.equals(100 * 10 ** fundsTokenDecimals)
    expect(Number(MPLBalancePost - MPLBalancePre)).to.equals(100 * 10 ** fundsTokenDecimals)

  })

  it('convert DAI to USDC via bilateral swap', async function () {
    
    expect(await mapleTreasury.convertERC20Bilateral(mintableDAIAddress))

  })

  it('supply some liquidity to Uniswap DAI / USDC pool', async function () {
    
    const accounts = await ethers.provider.listAccounts()
    const mintableDAIDecimals = await mintableDAI.decimals()
    const fundsTokenDecimals = await fundsToken.decimals()
    var a = BigNumber.from(mintableDAIDecimals)
    var b = BigNumber.from(fundsTokenDecimals)
    var c = BigNumber.from(10)
    var amountDAI = b.pow(c).mul(1000)
    var amountUSDC = a.pow(c).mul(1000)

    // mint DAI / USDC for accounts[0], mintSpecial() handles precision conversion
    expect(await mintableDAI.mintSpecial(accounts[0], 1000))
    expect(await fundsToken.mintSpecial(accounts[0], 1000))
    expect(await mintableDAI.approve(uniswapRouterAddress, amountDAI))
    expect(await fundsToken.approve(uniswapRouterAddress, amountUSDC))
    const returns = 0;
    expect(returns = await uniswapRouter.addLiquidity(
      mintableDAIAddress, 
      fundsTokenAddress,
      amountDAI,
      amountUSDC,
      amountDAI,
      amountUSDC,
      accounts[0],
      Math.floor(Date.now() / 1000) + 100
    ))

    console.log(returns)

  })

})
