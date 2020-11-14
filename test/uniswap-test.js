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
    mintableDAI = new ethers.Contract(mintableDAIAddress, mintableDAIABI, ethers.provider.getSigner(0))
    fundsToken = new ethers.Contract(fundsTokenAddress, fundsTokenABI, ethers.provider.getSigner(0))
    mapleTreasury = new ethers.Contract(treasuryAddress, treasuryABI, ethers.provider.getSigner(0))
    mapleToken = new ethers.Contract(mapleTokenAddress, mapleTokenABI, ethers.provider.getSigner(0))
    uniswapRouter = new ethers.Contract(uniswapRouterAddress, uniswapRouterABI,ethers.provider.getSigner(0))
    uniswapFactory = new ethers.Contract(uniswapFactoryAddress, uniswapFactoryABI, ethers.provider.getSigner(0))
  })

  /** 
    FAILURE_POINT_1
    UniswapPAIR: getReserves(x,y,z):
      x: 0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0
      y: 0xe7f1725e7734ce288f8367e1bb143e90bb3f0512
      z: 0x5fbdb2315678afecb367f032d93f642f64180aa3

    FAILURE_POINT_2
    LIBRARY:
    (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
    pairFor(factory, tokenA, tokenB) = 0x51be65159efe70dfbbb46c37334c4fb1beeca2c2
  */

  
  it('test FAILURE_POINT_1', async function () {
    
    const getPairAddress = await uniswapFactory.getPair(fundsTokenAddress, mintableDAIAddress);

    console.log("USDC/DAI UniswapPAIR: ", getPairAddress);
    console.log("FACTORY: ", "0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0")

    uniswapPair = new ethers.Contract(
      getPairAddress, 
      uniswapV2PairABI,
      ethers.provider.getSigner(0)
    )

   const getReserves = await uniswapPair.getReserves();
   console.log(getReserves);
  })

  it('test FAILURE_POINT_2', async function () {
    
    const accounts = await ethers.provider.listAccounts()
    const DAIDecimals = await mintableDAI.decimals()
    const USDCDecimals = await fundsToken.decimals()
    expect(await mintableDAI.mintSpecial(accounts[0], 100000))
    expect(await fundsToken.mintSpecial(accounts[0], 100000))
    expect(await mintableDAI.approve(uniswapRouterAddress, BigInt(100000 * 10**DAIDecimals)))
    expect(await fundsToken.approve(uniswapRouterAddress, BigInt(100000 * 10**USDCDecimals)))

    await expect(
      uniswapRouter.addLiquidity(
        mintableDAIAddress,
        fundsTokenAddress,
        BigInt(100000 * 10**DAIDecimals),
        BigInt(100000 * 10**USDCDecimals),
        0,
        0,
        accounts[0],
        1
      )
    ).to.be.revertedWith("UniswapV2Router: EXPIRED");

    expect(
      await uniswapRouter.addLiquidity(
        mintableDAIAddress,
        fundsTokenAddress,
        10,
        10,
        0,
        0,
        accounts[0],
        Math.floor(Date.now() / 1000) + 1000
      )
    )
    
  })

})
