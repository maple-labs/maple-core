
// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IStakeLocker.sol";


import "../BulletRepaymentCalc.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../StakeLockerFactory.sol";
import "../PoolFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../DebtLockerFactory.sol";
import "../DebtLocker.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../LoanFactory.sol";
import "../Loan.sol";
import "../Pool.sol";

interface IBPoolFactory {
    function newBPool() external returns (address);
}

contract PoolDelegate {
    function try_fundLoan(address pool1, address loan, address dlFactory1, uint256 amt) external returns (bool ok) {
        string memory sig = "fundLoan(address,address,uint256)";
        (ok,) = address(pool1).call(abi.encodeWithSignature(sig, loan, dlFactory1, amt));
    }

    function createPool(
        address liqPoolFactory, 
        address liqAsset,
        address stakeAsset,
        uint256 stakingFee,
        uint256 delegateFee
    ) 
        external returns (address liquidityPool) 
    {
        liquidityPool = IPoolFactory(liqPoolFactory).createPool(
            liqAsset,
            stakeAsset,
            stakingFee,
            delegateFee
        );
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function claim(address pool, address loan, address dlFactory) external returns(uint[5] memory) {
        return IPool(pool).claim(loan, dlFactory);  
    }

    function setPrincipalPenalty(address pool, uint256 penalty) external {
        return IPool(pool).setPrincipalPenalty(penalty);
    }

    function setInterestDelay(address pool, uint256 delay) external {
        return IPool(pool).setInterestDelay(delay);
    }
}

contract LP {
    function try_deposit(address pool1, uint256 amt)  external returns (bool ok) {
        string memory sig = "deposit(uint256)";
        (ok,) = address(pool1).call(abi.encodeWithSignature(sig, amt));
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function withdraw(address pool, uint256 amt) external {
        Pool(pool).withdraw(amt);
    }
}

contract Staker {
    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function unstake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).unstake(amt);
    }
    function joinBpool(address _bpool, address _ass, uint _amt) external returns (uint){
        return IBPool(_bpool).joinswapExternAmountIn(_ass,_amt, 10);
    }

}

contract StakeLockerTest is TestUtil {

    using SafeMath for uint256;

    ERC20                           fundsToken;
    MapleToken                             mpl;
    MapleGlobals                       globals;
    PoolFactory                 liqPoolFactory;
    StakeLockerFactory           stakeLFactory;
    LiquidityLockerFactory         liqLFactory;
    Pool                                 pool1; 
    DSValue                          ethOracle;
    DSValue                         usdcOracle;
    BulletRepaymentCalc             bulletCalc;
    LateFeeCalc                    lateFeeCalc;
    PremiumCalc                    premiumCalc;
    IBPool                               bPool;
    PoolDelegate                           sid;
    Staker                                 jim;
    CollateralLockerFactory          clFactory;
    FundingLockerFactory             flFactory;

    function setUp() public {

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = new MapleGlobals(address(this), address(mpl));
        stakeLFactory  = new StakeLockerFactory();
        liqLFactory    = new LiquidityLockerFactory();
        liqPoolFactory = new PoolFactory(address(globals), address(stakeLFactory), address(liqLFactory));
        ethOracle      = new DSValue();
        usdcOracle     = new DSValue();
        bulletCalc     = new BulletRepaymentCalc();
        lateFeeCalc    = new LateFeeCalc(0);   // Flat 0% fee
        premiumCalc    = new PremiumCalc(500); // Flat 5% premium
        sid            = new PoolDelegate();
        jim            = new Staker();

        ethOracle.poke(500 ether);  // Set ETH price to $600
        usdcOracle.poke(1 ether);    // Set USDC price to $1

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * USD);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), uint(-1));
        mpl.approve(address(bPool), uint(-1));

        bPool.bind(USDC, 50_000_000 * 10 ** 6, 5 ether);   // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl), 100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * USD);
        assertEq(mpl.balanceOf(address(bPool)),             100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized

        globals.setPoolDelegateWhitelist(address(sid), true);
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), bPool.balanceOf(address(this)) / 2);

        // Set Globals
        globals.setCalc(address(bulletCalc),  true);
        globals.setCalc(address(lateFeeCalc), true);
        globals.setCalc(address(premiumCalc), true);
        globals.setCollateralAsset(WETH, true);
        globals.setLoanAsset(USDC, true);
        globals.assignPriceFeed(WETH, address(ethOracle));
        globals.assignPriceFeed(USDC, address(usdcOracle));
        globals.setMapleBPool(address(bPool));
        globals.setMapleBPoolAssetPair(USDC);
        globals.setStakeRequired(100 * USD);

        // Create Liquidity Pool
        pool1 = Pool(sid.createPool(
            address(liqPoolFactory),
            USDC,
            address(bPool),
            500,
            100
        ));

    }
    function test_unstake_calculation() public {
        mint("USDC", address(jim), 50_000_000 * USD);
        jim.approve(USDC, address(bPool), uint(-1));

        uint jimbpt          = jim.joinBpool(address(bPool), USDC, 10_000_000 * USD);
        address stakeLocker1 = pool1.stakeLocker();
        jim.approve(address(bPool), stakeLocker1, uint(-1));

        jim.stake(stakeLocker1, jimbpt);
        uint start = block.timestamp;
        jim.approve(stakeLocker1, stakeLocker1, uint(-1));

        assertEq(IStakeLocker(stakeLocker1).getUnstakeableBalance(address(jim)), 0);

        hevm.warp(start + globals.unstakeDelay() / 36);
        withinPrecision(IStakeLocker(stakeLocker1).getUnstakeableBalance(address(jim)),IERC20(stakeLocker1).balanceOf(address(jim)) / 36, 6);

        hevm.warp(start + globals.unstakeDelay() / 2);
        withinPrecision(IStakeLocker(stakeLocker1).getUnstakeableBalance(address(jim)),IERC20(stakeLocker1).balanceOf(address(jim)) / 2, 6);

        hevm.warp(start + globals.unstakeDelay() + 1);
        assertEq(IStakeLocker(stakeLocker1).getUnstakeableBalance(address(jim)), IERC20(stakeLocker1).balanceOf(address(jim)));

        hevm.warp(start + globals.unstakeDelay() + 3600 * 1000);
        assertEq(IStakeLocker(stakeLocker1).getUnstakeableBalance(address(jim)), IERC20(stakeLocker1).balanceOf(address(jim)));
    }

}
