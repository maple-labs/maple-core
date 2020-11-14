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

  it('add liquidity to DAI/USDC pool', async function () {
    
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

  })

  it('call read functions from uniswapPair to confirm state vars', async function () {

    const getPairAddress = await uniswapFactory.getPair(fundsTokenAddress, mintableDAIAddress);

    uniswapPair = new ethers.Contract(
      getPairAddress, 
      uniswapV2PairABI, 
      ethers.provider.getSigner(0)
    )

    const pairToken0 = await uniswapPair.token0();
    const pairToken1 = await uniswapPair.token1();
    expect(pairToken0).to.equals(fundsTokenAddress);
    expect(pairToken1).to.equals(mintableDAIAddress);

    const getReserves = await uniswapPair.getReserves()

    expect(parseInt(getReserves["_reserve0"]["_hex"]) / 10e6).to.equals(1000);
    expect(parseInt(getReserves["_reserve1"]["_hex"]) / 10e18).to.equals(1000);

  })

  it('ensure uniswapRouter is pointing to unsiwapFactory', async function() {
    const factoryAddress = await uniswapRouter.factory()
    expect(factoryAddress).to.equals(uniswapFactoryAddress)
  })

  it('call getAmountsOut() from uniswapRouter to ensure liquidity in USDC/DAI pool', async function () {

    /**
      TODO: Identify why we're unable to call getAmountsOut() ... uniswapRouter accesses UniswapV2Library to call:
      
      function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
          (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
          amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
      }

      Could there be a problem with getReserves() or getAmountOut()** unique to getAmountsOut()**

      function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
      }

      function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
      }

    */
    // Debug getReserves()
    const getPairAddress = await uniswapFactory.getPair(fundsTokenAddress, mintableDAIAddress);
    uniswapPair = new ethers.Contract(getPairAddress, uniswapV2PairABI, ethers.provider.getSigner(0))

    const getReservesDAIUSDC = await uniswapPair.getReserves();

    console.log(getReservesDAIUSDC)

    const getAmountsA = await uniswapRouter.getAmountsOut(
      100,
      [fundsTokenAddress, mintableDAIAddress]
    )
    
    console.log(getAmountsA)
  })

  it('look through events on DAI / USDC Uniswap pair', async function () {

    // TODO: Identify an alternative package to read historical events on-chain. ethers.js doesn't cut it.
    
    // const getPairAddress = await uniswapFactory.getPair(mintableDAIAddress, fundsTokenAddress);
    
    // uniswapPair = new ethers.Contract(
    //   getPairAddress, 
    //   uniswapV2PairABI, 
    //   ethers.provider.getSigner(0)
    // )

    // const mintEvents = await uniswapPair.Mint();
    // console.log(mintEvents);

    // expect(await fundsToken.transfer(mintableDAIAddress, 1));
    // expect(await fundsToken.transfer(mintableDAIAddress, 1));
    // expect(await fundsToken.transfer(mintableDAIAddress, 1));
    // expect(await fundsToken.transfer(mintableDAIAddress, 1));
    // expect(await mintableDAI.transfer(fundsTokenAddress, 1));
    // expect(await mintableDAI.transfer(fundsTokenAddress, 1));
    // expect(await mintableDAI.transfer(fundsTokenAddress, 1));
    // expect(await mintableDAI.transfer(fundsTokenAddress, 1));

    // const MPLTransferEvents = await fundsToken.Transfer();
    // console.log(MPLTransferEvents);
    
    // const DAITransferEvents = await mintableDAI.Transfer();
    // console.log(DAITransferEvents);
    
  })

  it('attempt via personal wallet, convert DAI to USDC', async function () {
  
    const accounts = await ethers.provider.listAccounts()
    const DAIDecimals = await mintableDAI.decimals()
    let personalDAIBalance = await mintableDAI.balanceOf(accounts[0])
    personalDAIBalance = parseInt(personalDAIBalance["_hex"]) / 10**DAIDecimals

    const amountToApproveDAI = BigInt(10 * 10**DAIDecimals)
    expect(await mintableDAI.approve(uniswapRouterAddress, amountToApproveDAI))

    expect(await uniswapRouter.swapExactTokensForTokens(
      amountToApproveDAI,
      0,
      [fundsTokenAddress, mintableDAIAddress],
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
