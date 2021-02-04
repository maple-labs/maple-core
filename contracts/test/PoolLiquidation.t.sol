
// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "./user/Governor.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IStakeLocker.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IERC20Details.sol";

import "../BulletRepaymentCalc.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
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

    function createPool(
        address poolFactory, 
        address liquidityAsset,
        address stakeAsset,
        address slFactory, 
        address llFactory,
        uint256 stakingFee,
        uint256 delegateFee,
        uint256 liquidityCap
    ) 
        external returns (address liquidityPool) 
    {
        liquidityPool = IPoolFactory(poolFactory).createPool(
            liquidityAsset,
            stakeAsset,
            slFactory,
            llFactory,
            stakingFee,
            delegateFee,
            liquidityCap
        );
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function finalize(address pool) external {
        IPool(pool).finalize();
    }

    function unstake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).unstake(amt);
    }

    function fundLoan(address pool, address loan, address dlFactory, uint256 amt) external {
        IPool(pool).fundLoan(loan, dlFactory, amt);  
    }

    function claim(address pool, address loan, address dlFactory) external returns(uint256[7] memory) {
        return IPool(pool).claim(loan, dlFactory);  
    }
}

contract Staker {

    function try_stake(address stakeLocker, uint256 amt) external returns(bool ok) {
        string memory sig = "stake(uint256)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, amt));
    }

    function try_unstake(address stakeLocker, uint256 amt) external returns(bool ok) {
        string memory sig = "unstake(uint256)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, amt));
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function unstake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).unstake(amt);
    }

}

contract LP {

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function withdraw(address pool, uint256 amt) external {
        Pool(pool).withdraw(amt);
    }

    function deposit(address pool, uint256 amt) external {
        Pool(pool).deposit(amt);
    }
}

contract Borrower {

    function makePayment(address loan) external {
        Loan(loan).makePayment();
    }

    function makeFullPayment(address loan) external {
        Loan(loan).makeFullPayment();
    }

    function drawdown(address loan, uint256 _drawdownAmount) external {
        Loan(loan).drawdown(_drawdownAmount);
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function createLoan(
        LoanFactory loanFactory,
        address loanAsset, 
        address collateralAsset, 
        address flFactory,
        address clFactory,
        uint256[6] memory specs,
        address[3] memory calcs
    ) 
        external returns (Loan loanVault) 
    {
        loanVault = Loan(
            loanFactory.createLoan(loanAsset, collateralAsset, flFactory, clFactory, specs, calcs)
        );
    }
}

contract Treasury { }

contract PoolLiquidationTest is TestUtil {

    using SafeMath for uint256;

    Governor                               gov;
    MapleToken                             mpl;
    MapleGlobals                       globals;
    FundingLockerFactory             flFactory;
    CollateralLockerFactory          clFactory;
    LoanFactory                    loanFactory;
    Loan                                  loan;
    PoolFactory                    poolFactory;
    StakeLockerFactory               slFactory;
    LiquidityLockerFactory           llFactory; 
    DebtLockerFactory                dlFactory;  
    Pool                                pool_a;  
    Pool                                pool_b; 
    DSValue                          ethOracle;
    DSValue                         usdcOracle;
    BulletRepaymentCalc             bulletCalc;
    LateFeeCalc                    lateFeeCalc;
    PremiumCalc                    premiumCalc;
    IBPool                               bPool;
    PoolDelegate                           sid;
    PoolDelegate                           joe;
    LP                                     ali;
    Borrower                               bob;
    Staker                                 che;
    Staker                                 dan;
    Treasury                               trs;
    IStakeLocker                 stakeLocker_a;
    IStakeLocker                 stakeLocker_b;

    uint256 constant public MAX_UINT = uint(-1);

    function setUp() public {

        gov            = new Governor();
        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        flFactory      = new FundingLockerFactory();         // Setup the FL factory to facilitate Loan factory functionality.
        clFactory      = new CollateralLockerFactory();      // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory    = new LoanFactory(address(globals));  // Create Loan factory.
        slFactory      = new StakeLockerFactory();           // Setup the SL factory to facilitate Pool factory functionality.
        llFactory      = new LiquidityLockerFactory();       // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory    = new PoolFactory(address(globals));  // Create pool factory.
        dlFactory      = new DebtLockerFactory();            // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        ethOracle      = new DSValue();                      // ETH Oracle.
        usdcOracle     = new DSValue();                      // USD Oracle.
        bulletCalc     = new BulletRepaymentCalc();          // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                 // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);               // Flat 5% premium
        sid            = new PoolDelegate();                 // Actor: Manager of the pool_a.
        joe            = new PoolDelegate();                 // Actor: Manager of the pool_b.
        ali            = new LP();                           // Actor: Liquidity providers
        bob            = new Borrower();                     // Actor: Borrower aka Loan contract creator.
        che            = new Staker();                       // Actor: Staker of BPTs
        dan            = new Staker();                       // Actor: Staker of BPTs
        trs            = new Treasury();                     // Treasury.

        gov.setValidLoanFactory(address(loanFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);

        gov.setDefaultUniswapPath(WETH, USDC, USDC);
        gov.setDefaultUniswapPath(WBTC, USDC, WETH);

        ethOracle.poke(500 ether);  // Set ETH price to $500
        usdcOracle.poke(1 ether);   // Set USDC price to $1

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * USD);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool), MAX_UINT);

        bPool.bind(USDC, 50_000_000 * USD, 5 ether);       // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl), 100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * USD);
        assertEq(mpl.balanceOf(address(bPool)),             100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized

        gov.setPoolDelegateWhitelist(address(sid), true);
        gov.setPoolDelegateWhitelist(address(joe), true);
        gov.setMapleTreasury(address(trs));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), 25 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(joe), 25 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(che), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
        bPool.transfer(address(dan), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool

        // Set Globals
        gov.setCalc(address(bulletCalc),  true);
        gov.setCalc(address(lateFeeCalc), true);
        gov.setCalc(address(premiumCalc), true);
        gov.setCollateralAsset(WETH, true);
        gov.setLoanAsset(USDC, true);
        gov.assignPriceFeed(WETH, address(ethOracle));
        gov.assignPriceFeed(USDC, address(usdcOracle));
        gov.setSwapOutRequired(1_000_000);

        // Create Liquidity Pool A
        pool_a = Pool(sid.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT  // liquidityCap value
        ));

        // Create Liquidity Pool
        pool_b = Pool(joe.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT  // liquidityCap value
        ));

        stakeLocker_a = IStakeLocker(pool_a.stakeLocker());
        stakeLocker_b = IStakeLocker(pool_b.stakeLocker());

        // loan Specifications
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        loan = bob.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        // Stake and finalize pool
        sid.approve(address(bPool), address(stakeLocker_a), 25 * WAD);
        joe.approve(address(bPool), address(stakeLocker_b), 25 * WAD);
        sid.stake(address(stakeLocker_a), 25 * WAD);
        joe.stake(address(stakeLocker_b), 25 * WAD);
        sid.finalize(address(pool_a));
        joe.finalize(address(pool_b));

        assertEq(uint256(pool_a.poolState()), 1);  // Finalize
        assertEq(uint256(pool_b.poolState()), 1);  // Finalize
    }

    function setUpLoanAndDefault() public {
        // Fund the pool
        mint("USDC", address(ali), 20_000_000 * USD);
        ali.approve(USDC, address(pool_a), MAX_UINT);
        ali.approve(USDC, address(pool_b), MAX_UINT);
        ali.deposit(address(pool_a), 10_000_000 * USD);
        ali.deposit(address(pool_b), 10_000_000 * USD);

        // Fund the loan
        sid.fundLoan(address(pool_a), address(loan), address(dlFactory), 1_000_000 * USD);
        joe.fundLoan(address(pool_b), address(loan), address(dlFactory), 3_000_000 * USD);
        uint cReq = loan.collateralRequiredForDrawdown(4_000_000 * USD);

        // Drawdown loan
        mint("WETH", address(bob), cReq);
        bob.approve(WETH, address(loan), MAX_UINT);
        bob.drawdown(address(loan), 4_000_000 * USD);
        
        // Warp to late payment
        uint256 start = block.timestamp;
        uint256 nextPaymentDue = loan.nextPaymentDue();
        uint256 gracePeriod = globals.gracePeriod();
        hevm.warp(start + nextPaymentDue + gracePeriod + 1);

        // Trigger default
        loan.triggerDefault();
    }

    function test_claim_default_info() public {

        setUpLoanAndDefault();

        /**
            Now that triggerDefault() is called, the return value defaultSuffered
            will be greater than 0. Calling claim() is the mechanism which settles,
            or rather updates accounting in the Pool which in turn will enable us
            to handle liquidation of BPTs in the Stake Locker accurately.
        */
        uint256[7] memory vals_a = sid.claim(address(pool_a), address(loan),  address(dlFactory));
        uint256[7] memory vals_b = joe.claim(address(pool_b), address(loan),  address(dlFactory));

        // Non-zero value is passed through.
        assertEq(vals_a[5], loan.defaultSuffered() * (1_000_000 * WAD) / (4_000_000 * WAD));
        assertEq(vals_b[5], loan.defaultSuffered() * (3_000_000 * WAD) / (4_000_000 * WAD));
        withinPrecision(vals_a[5] + vals_b[5], loan.defaultSuffered(), 2);
    }

    function test_claim_default_burn_BPT() public {

        setUpLoanAndDefault();

        address liquidityLocker_a = pool_a.liquidityLocker();
        address liquidityLocker_b = pool_b.liquidityLocker();

        // Pre-state liquidityLocker checks.
        uint256 liquidityLocker_pre_a = IERC20(USDC).balanceOf(liquidityLocker_a);
        uint256 liquidityLocker_pre_b = IERC20(USDC).balanceOf(liquidityLocker_b);

        uint256[7] memory vals_a = sid.claim(address(pool_a), address(loan),  address(dlFactory));
        uint256[7] memory vals_b = joe.claim(address(pool_b), address(loan),  address(dlFactory));

        // Post-state liquidityLocker checks.
        uint256 liquidityLocker_post_a = IERC20(USDC).balanceOf(liquidityLocker_a);
        uint256 liquidityLocker_post_b = IERC20(USDC).balanceOf(liquidityLocker_b);
        
        assertEq(liquidityLocker_post_a - liquidityLocker_pre_a, vals_a[5]);
        assertEq(liquidityLocker_post_b - liquidityLocker_pre_b, vals_b[5]);
        assertGt(vals_a[5], 0);
        assertGt(vals_b[5], 0);
      
    }
} 
