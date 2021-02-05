// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/LP.sol";
import "./user/PoolDelegate.sol";

import "../interfaces/IBFactory.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IStakeLocker.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IERC20Details.sol";

import "../LateFeeCalc.sol";

import "../BulletRepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../DebtLocker.sol";
import "../DebtLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../Loan.sol";
import "../LoanFactory.sol";
import "../MapleToken.sol";
import "../PoolFactory.sol";
import "../Pool.sol";
import "../PremiumCalc.sol";
import "../StakeLockerFactory.sol";

import "../mocks/token.sol";
import "../mocks/value.sol";

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Treasury { }

contract PoolTest is TestUtil {

    using SafeMath for uint256;

    Borrower                               eli;
    Borrower                               fay;
    Borrower                               hal;
    Governor                               gov;
    LP                                     bob;
    LP                                     che;
    LP                                     dan;
    LP                                     kim;
    PoolDelegate                           sid;
    PoolDelegate                           joe;

    ERC20                           fundsToken;
    MapleToken                             mpl;
    MapleGlobals                       globals;
    FundingLockerFactory             flFactory;
    CollateralLockerFactory          clFactory;
    LoanFactory                    loanFactory;
    Loan                                  loan;
    Loan                                 loan2;
    Loan                                 loan3;
    PoolFactory                    poolFactory;
    StakeLockerFactory               slFactory;
    LiquidityLockerFactory           llFactory; 
    DebtLockerFactory               dlFactory1; 
    DebtLockerFactory               dlFactory2; 
    Pool                                 pool1; 
    Pool                                 pool2; 
    BulletRepaymentCalc             bulletCalc;
    LateFeeCalc                    lateFeeCalc;
    PremiumCalc                    premiumCalc;
    Treasury                               trs;
    
    IBPool                               bPool;

    uint256 constant public MAX_UINT = uint(-1);

    function setUp() public {

        eli            = new Borrower();                                                // Actor: Borrower of the Loan.
        fay            = new Borrower();                                                // Actor: Borrower of the Loan.
        hal            = new Borrower();                                                // Actor: Borrower of the Loan.
        gov            = new Governor();                                                // Actor: Governor of Maple.
        sid            = new PoolDelegate();                                            // Actor: Manager of the Pool.
        joe            = new PoolDelegate();                                            // Actor: Manager of the Pool.
        bob            = new LP();                                                      // Actor: Liquidity provider.
        che            = new LP();                                                      // Actor: Liquidity provider.
        dan            = new LP();                                                      // Actor: Liquidity provider.
        kim            = new LP();                                                      // Actor: Liquidity provider.

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        flFactory      = new FundingLockerFactory();                                    // Setup the FL factory to facilitate Loan factory functionality.
        clFactory      = new CollateralLockerFactory();                                 // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory    = new LoanFactory(address(globals));                             // Create Loan factory.
        slFactory      = new StakeLockerFactory();                                      // Setup the SL factory to facilitate Pool factory functionality.
        llFactory      = new LiquidityLockerFactory();                                  // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory    = new PoolFactory(address(globals));                             // Create pool factory.
        dlFactory1     = new DebtLockerFactory();                                       // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        dlFactory2     = new DebtLockerFactory();                                       // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        bulletCalc     = new BulletRepaymentCalc();                                     // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                                            // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);                                          // Flat 5% premium
        trs            = new Treasury();                                                // Treasury.

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory1), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory2), true);

        gov.setPriceOracle(WETH, 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        gov.setPriceOracle(WBTC, 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
        gov.setPriceOracle(USDC, 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * USD);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool());

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

        bPool.transfer(address(sid), bPool.balanceOf(address(this)) / 2);
        bPool.transfer(address(joe), bPool.balanceOf(address(this)));

        // Set Globals
        gov.setCalc(address(bulletCalc),  true);
        gov.setCalc(address(lateFeeCalc), true);
        gov.setCalc(address(premiumCalc), true);
        gov.setCollateralAsset(WETH, true);
        gov.setLoanAsset(USDC, true);
        gov.setSwapOutRequired(1_000_000);

        // Create Liquidity Pool
        pool1 = Pool(sid.createPool(
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
        pool2 = Pool(joe.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            7500,
            50,
            MAX_UINT // liquidityCap value
        ));

        // loan Specifications
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        loan  = eli.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan2 = fay.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan3 = hal.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
    }

    function test_getInitialStakeRequirements() public {
        uint256 minCover; uint256 minCover2; uint256 curCover;
        uint256 minStake; uint256 minStake2; uint256 curStake;
        uint256 calc_minStake; uint256 calc_stakerBal;
        bool covered;

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        address stakeLocker = pool1.stakeLocker();
        sid.approve(address(bPool), stakeLocker, MAX_UINT);

        // Pre-state checks.
        assertEq(bPool.balanceOf(address(sid)),                 50 * WAD);  // PD has 50 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                         0);  // Nothing staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),          0);  // Nothing staked

        (minCover, curCover, covered, minStake, curStake) = pool1.getInitialStakeRequirements();

        (calc_minStake, calc_stakerBal) = pool1.getPoolSharesRequired(address(bPool), USDC, address(sid), stakeLocker, minCover);

        assertEq(minCover, globals.swapOutRequired() * USD);              // Equal to globally specified value
        assertEq(curCover, 0);                                            // Nothing staked
        assertTrue(!covered);                                             // Not covered
        assertEq(minStake, calc_minStake);                                // Mininum stake equals calculated minimum stake     
        assertEq(curStake, calc_stakerBal);                               // Current stake equals calculated stake
        assertEq(curStake, IERC20(stakeLocker).balanceOf(address(sid)));  // Current stake equals balance of stakeLocker FDTs

        /***************************************/
        /*** Stake Less than Required Amount ***/
        /***************************************/
        sid.stake(stakeLocker, minStake - 1);

        // Post-state checks.
        assertEq(bPool.balanceOf(address(sid)),                50 * WAD - (minStake - 1));  // PD staked minStake - 1 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                             minStake - 1);   // minStake - 1 BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),              minStake - 1);   // PD has minStake - 1 SL tokens

        (minCover2, curCover, covered, minStake2, curStake) = pool1.getInitialStakeRequirements();

        (, calc_stakerBal) = pool1.getPoolSharesRequired(address(bPool), USDC, address(sid), stakeLocker, minCover);

        assertEq(minCover2, minCover);                                    // Doesn't change
        assertTrue(curCover < minCover);                                  // Not enough cover
        assertTrue(!covered);                                             // Not covered
        assertEq(minStake2, minStake);                                    // Doesn't change
        assertEq(curStake, calc_stakerBal);                               // Current stake equals calculated stake
        assertEq(curStake, IERC20(stakeLocker).balanceOf(address(sid)));  // Current stake equals balance of stakeLocker FDTs

        /***********************************/
        /*** Stake Exact Required Amount ***/
        /***********************************/
        sid.stake(stakeLocker, 1); // Add one more wei of BPT to get to minStake amount

        // Post-state checks.
        assertEq(bPool.balanceOf(address(sid)),                50 * WAD - minStake);  // PD staked minStake
        assertEq(bPool.balanceOf(stakeLocker),                            minStake);  // minStake BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),             minStake);  // PD has minStake SL tokens

        (minCover2, curCover, covered, minStake2, curStake) = pool1.getInitialStakeRequirements();

        (, calc_stakerBal) = pool1.getPoolSharesRequired(address(bPool), USDC, address(sid), stakeLocker, minCover);

        assertEq(minCover2, minCover);                                    // Doesn't change
        withinPrecision(curCover, minCover, 6);                           // Roughly enough
        assertTrue(covered);                                              // Covered
        assertEq(minStake2, minStake);                                    // Doesn't change
        assertEq(curStake, calc_stakerBal);                               // Current stake equals calculated stake
        assertEq(curStake, IERC20(stakeLocker).balanceOf(address(sid)));  // Current stake equals balance of stakeLocker FDTs
    }

    function test_stake_and_finalize() public {

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        address stakeLocker = pool1.stakeLocker();
        sid.approve(address(bPool), stakeLocker, uint(-1));

        // Pre-state checks.
        assertEq(bPool.balanceOf(address(sid)),                 50 * WAD);  // PD has 50 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                         0);  // Nothing staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),          0);  // Nothing staked

        /***************************************/
        /*** Stake Less than Required Amount ***/
        /***************************************/
        (,,, uint256 minStake,) = pool1.getInitialStakeRequirements();
        sid.stake(pool1.stakeLocker(), minStake - 1);

        // Post-state checks.
        assertEq(bPool.balanceOf(address(sid)),                50 * WAD - (minStake - 1));  // PD staked minStake - 1 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                             minStake - 1);   // minStake - 1 BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),              minStake - 1);   // PD has minStake - 1 SL tokens

        assertTrue(!sid.try_finalize(address(pool1)));  // Can't finalize

        /***********************************/
        /*** Stake Exact Required Amount ***/
        /***********************************/
        sid.stake(stakeLocker, 1); // Add one more wei of BPT to get to minStake amount

        // Post-state checks.
        assertEq(bPool.balanceOf(address(sid)),                50 * WAD - minStake);  // PD staked minStake
        assertEq(bPool.balanceOf(stakeLocker),                            minStake);  // minStake BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),             minStake);  // PD has minStake SL tokens
        assertEq(uint256(pool1.poolState()), 0);  // Initialized

        assertTrue(!joe.try_finalize(address(pool1)));  // Can't finalize if not PD
        assertTrue( sid.try_finalize(address(pool1)));  // PD that staked can finalize

        assertEq(uint256(pool1.poolState()), 1);  // Finalized
    }

    function test_deposit() public {
        address stakeLocker = pool1.stakeLocker();
        address liqLocker   = pool1.liquidityLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        // Mint 100 USDC into this LP account
        mint("USDC", address(bob), 100 * USD);

        assertTrue(!bob.try_deposit(address(pool1), 100 * USD)); // Not finalized

        sid.finalize(address(pool1));

        assertTrue(!bob.try_deposit(address(pool1), 100 * USD)); // Not approved

        bob.approve(USDC, address(pool1), MAX_UINT);

        assertEq(IERC20(USDC).balanceOf(address(bob)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(liqLocker),            0);
        assertEq(pool1.balanceOf(address(bob)),                0);

        assertTrue(bob.try_deposit(address(pool1),    100 * USD));

        assertEq(IERC20(USDC).balanceOf(address(bob)),         0);
        assertEq(IERC20(USDC).balanceOf(liqLocker),    100 * USD);
        assertEq(pool1.balanceOf(address(bob)),        100 * WAD);
    }

    function test_deposit_with_liquidity_cap() public {
    
        address stakeLocker = pool1.stakeLocker();
        address liqLocker   = pool1.liquidityLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        // Mint 1000 USDC into this LP account
        mint("USDC", address(bob), 10000 * USD);

        sid.finalize(address(pool1));
        sid.setPrincipalPenalty(address(pool1), 0);

        bob.approve(USDC, address(pool1), MAX_UINT);

        // Changes the `liquidityCap`.
        assertTrue(sid.try_setLiquidityCap(address(pool1), 900 * USD), "Failed to set liquidity cap");
        assertEq(pool1.liquidityCap(), 900 * USD, "Incorrect value set for liquidity cap");

        // Not able to deposit as cap is lower than the deposit amount.
        assertTrue(!pool1.isDepositAllowed(1000 * USD), "Deposit should not be allowed because 900 USD < 1000 USD");
        assertTrue(!bob.try_deposit(address(pool1), 1000 * USD), "Should not able to deposit 1000 USD");

        // Tries with lower amount it will pass.
        assertTrue(pool1.isDepositAllowed(500 * USD), "Deposit should be allowed because 900 USD > 500 USD");
        assertTrue(bob.try_deposit(address(pool1), 500 * USD), "Fail to deposit 500 USD");

        // Bob tried again with 600 USDC it fails again.
        assertTrue(!pool1.isDepositAllowed(600 * USD), "Deposit should not be allowed because 900 USD < 500 + 600 USD");
        assertTrue(!bob.try_deposit(address(pool1), 600 * USD), "Should not able to deposit 600 USD");

        // Set liquidityCap to zero and withdraw
        assertTrue(sid.try_setLiquidityCap(address(pool1), 0),           "Failed to set liquidity cap");
        assertTrue(sid.try_setLockupPeriod(address(pool1), 0),           "Failed to set the lockup period");
        assertEq(pool1.lockupPeriod(), uint256(0),              "Failed to update the lockup period");
        
        (uint claimable, uint principal, uint interest) = pool1.claimableFunds(address(bob));

        assertEq(claimable, 500 * USD);
        assertTrue(bob.try_withdraw(address(pool1), claimable), "Failed to withdraw 500 USD");
    }

    function test_deposit_depositDate() public {
        address stakeLocker = pool1.stakeLocker();
        address liqLocker   = pool1.liquidityLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);
        
        // Mint 100 USDC into this LP account
        mint("USDC", address(bob), 200 * USD);
        bob.approve(USDC, address(pool1), MAX_UINT);
        sid.finalize(address(pool1));

        // Deposit 100 USDC on first day
        uint256 startDate = block.timestamp;

        uint256 initialAmt = 100 * USD;

        bob.deposit(address(pool1), 100 * USD);
        assertEq(pool1.depositDate(address(bob)), startDate);

        uint256 newAmt = 20 * USD;

        hevm.warp(startDate + 30 days);
        bob.deposit(address(pool1), newAmt);
        uint256 coef = newAmt * WAD / (newAmt + initialAmt);

        uint256 newDepDate = startDate + coef * (block.timestamp - startDate) / WAD;
        assertEq(pool1.depositDate(address(bob)), newDepDate);  // Gets updated

        assertTrue(sid.try_setLockupPeriod(address(pool1), uint256(0)));  // Sets 0 as lockup period to allow withdraw. 
        bob.withdraw(address(pool1), newAmt);

        assertEq(pool1.depositDate(address(bob)), newDepDate);  // Doesn't change
    }

    function test_fundLoan() public {
        address stakeLocker   = pool1.stakeLocker();
        address liqLocker     = pool1.liquidityLocker();
        address fundingLocker = loan.fundingLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        // Mint 100 USDC into this LP account
        mint("USDC", address(bob), 100 * USD);

        sid.finalize(address(pool1));

        bob.approve(USDC, address(pool1), MAX_UINT);

        assertTrue(bob.try_deposit(address(pool1), 100 * USD));

        assertTrue(!sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 100 * USD)); // LoanFactory not in globals

        gov.setValidLoanFactory(address(loanFactory), true);

        assertEq(IERC20(USDC).balanceOf(liqLocker),               100 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),          0);  // Balance of Funding Locker
        
        /*******************/
        /*** Fund a Loan ***/
        /*******************/
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 20 * USD), "Fail to fund a loan");  // Fund loan for 20 USDC

        DebtLocker debtLocker = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));

        assertEq(address(debtLocker.loan()), address(loan));
        assertEq(debtLocker.owner(), address(pool1));
        assertEq(address(debtLocker.loanAsset()), USDC);

        assertEq(IERC20(USDC).balanceOf(liqLocker),              80 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 20 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),    20 * WAD);  // LoanToken balance of LT Locker
        assertEq(pool1.principalOut(),                           20 * USD);  // Outstanding principal in liqiudity pool 1

        /****************************************/
        /*** Fund same loan with the same LTL ***/
        /****************************************/
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 25 * USD)); // Fund same loan for 25 USDC

        assertEq(dlFactory1.owner(address(debtLocker)), address(pool1));
        assertTrue(dlFactory1.isLocker(address(debtLocker)));

        assertEq(IERC20(USDC).balanceOf(liqLocker),              55 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 45 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),    45 * WAD);  // LoanToken balance of LT Locker
        assertEq(pool1.principalOut(),                           45 * USD);  // Outstanding principal in liqiudity pool 1

        /*******************************************/
        /*** Fund same loan with a different LTL ***/
        /*******************************************/
        DebtLockerFactory dlFactory2 = new DebtLockerFactory();
        gov.setValidSubFactory(address(poolFactory), address(dlFactory2), true);
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory2), 10 * USD)); // Fund loan for 15 USDC

        DebtLocker debtLocker2 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory2)));

        assertEq(address(debtLocker2.loan()), address(loan));
        assertEq(debtLocker2.owner(), address(pool1));
        assertEq(address(debtLocker2.loanAsset()), USDC);

        assertEq(dlFactory2.owner(address(debtLocker2)), address(pool1));
        assertTrue(dlFactory2.isLocker(address(debtLocker2)));

        assertEq(IERC20(USDC).balanceOf(liqLocker),              45 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 55 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker2)),   10 * WAD);  // LoanToken balance of LT Locker 2
        assertEq(pool1.principalOut(),                           55 * USD);  // Outstanding principal in liqiudity pool 1
    }

    function checkClaim(DebtLocker debtLocker, Loan loan, PoolDelegate pd, IERC20 reqAsset, Pool pool, address dlFactory) internal {
        uint256[10] memory balances = [
            reqAsset.balanceOf(address(debtLocker)),
            reqAsset.balanceOf(address(pool)),
            reqAsset.balanceOf(address(pd)),
            reqAsset.balanceOf(pool.stakeLocker()),
            reqAsset.balanceOf(pool.liquidityLocker()),
            0,0,0,0,0
        ];

        uint256[4] memory loanData = [
            loan.interestPaid(),
            loan.principalPaid(),
            loan.feePaid(),
            loan.excessReturned()
        ];

        uint256[8] memory debtLockerData = [
            debtLocker.interestPaid(),
            debtLocker.principalPaid(),
            debtLocker.feePaid(),
            debtLocker.excessReturned(),
            0,0,0,0
        ];

        uint256 beforePrincipalOut = pool.principalOut();
        uint256 beforeInterestSum  = pool.interestSum();
        uint256[7] memory claim = pd.claim(address(pool), address(loan),   address(dlFactory));

        // Updated LTL state variables
        debtLockerData[4] = debtLocker.interestPaid();
        debtLockerData[5] = debtLocker.principalPaid();
        debtLockerData[6] = debtLocker.feePaid();
        debtLockerData[7] = debtLocker.excessReturned();

        balances[5] = reqAsset.balanceOf(address(debtLocker));
        balances[6] = reqAsset.balanceOf(address(pool));
        balances[7] = reqAsset.balanceOf(address(pd));
        balances[8] = reqAsset.balanceOf(pool.stakeLocker());
        balances[9] = reqAsset.balanceOf(pool.liquidityLocker());

        uint256 sumTransfer;
        uint256 sumNetNew;

        for(uint i = 0; i < 4; i++) sumNetNew += (loanData[i] - debtLockerData[i]);

        {
            for(uint i = 0; i < 4; i++) {
                assertEq(debtLockerData[i + 4], loanData[i]);  // LTL updated to reflect loan state

                // Category portion of claim * LTL asset balance 
                // Eg. (interestClaimed / totalClaimed) * balance = Portion of total claim balance that is interest
                uint256 loanShare = (loanData[i] - debtLockerData[i]) * 1 ether / sumNetNew * claim[0] / 1 ether;
                assertEq(loanShare, claim[i + 1]);

                sumTransfer += balances[i + 6] - balances[i + 1]; // Sum up all transfers that occured from claim
            }
            assertEq(claim[0], sumTransfer); // Assert balance from withdrawFunds equals sum of transfers
        }

        {
            assertEq(balances[5] - balances[0], 0);      // LTL locker should have transferred ALL funds claimed to LP
            assertTrue(balances[6] - balances[1] < 10);  // LP         should have transferred ALL funds claimed to LL, SL, and PD (with rounding error)

            assertEq(balances[7] - balances[2], claim[3] + claim[1] * pool.delegateFee() / 10_000);  // Pool delegate claim (feePaid + delegateFee portion of interest)
            assertEq(balances[8] - balances[3],            claim[1] * pool.stakingFee()  / 10_000);  // Staking Locker claim (feePaid + stakingFee portion of interest)

            withinPrecision(pool.interestSum() - beforeInterestSum, claim[1] - claim[1] * (pool.delegateFee() + pool.stakingFee()) / 10_000, 11);  // interestSum incremented by remainder of interest

            // Liquidity Locker balance change should EXACTLY equal state variable change
            assertEq(balances[9] - balances[4], (beforePrincipalOut - pool.principalOut()) + (pool.interestSum() - beforeInterestSum));

            assertTrue(beforePrincipalOut - pool.principalOut() == claim[2] + claim[4]); // principalOut incremented by claimed principal + excess
        }
    }

    function isConstantPoolValue(Pool pool, IERC20 loanAsset, uint256 constPoolVal) internal returns(bool) {
        return pool.principalOut() + loanAsset.balanceOf(pool.liquidityLocker()) == constPoolVal;
    }

    function assertConstFundLoan(Pool pool, address loan, address dlFactory, uint256 amt, IERC20 loanAsset, uint256 constPoolVal) internal returns(bool) {
        assertTrue(sid.try_fundLoan(address(pool), loan,  dlFactory, amt));
        assertTrue(isConstantPoolValue(pool1, loanAsset, constPoolVal));
    }

    function assertConstClaim(Pool pool, address loan, address dlFactory, IERC20 loanAsset, uint256 constPoolVal) internal returns(bool) {
        sid.claim(address(pool), loan, dlFactory);
        assertTrue(isConstantPoolValue(pool, loanAsset, constPoolVal));
    }

    function test_claim_principal_accounting() public {
        /*********************************************/
        /*** Create a loan with 0% APR, 0% premium ***/
        /*********************************************/
        premiumCalc = new PremiumCalc(0); // Flat 0% premium
        gov.setCalc(address(premiumCalc), true);

        uint256[6] memory specs = [0, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        loan  = eli.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan2 = fay.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            sid.approve(address(bPool), pool1.stakeLocker(), uint(-1));
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

            sid.finalize(address(pool1));
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("USDC", address(bob), 1_000_000_000 * USD);
            mint("USDC", address(che), 1_000_000_000 * USD);
            mint("USDC", address(dan), 1_000_000_000 * USD);

            bob.approve(USDC, address(pool1), uint(-1));
            che.approve(USDC, address(pool1), uint(-1));
            dan.approve(USDC, address(pool1), uint(-1));

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 * USD));  // 10%
            assertTrue(che.try_deposit(address(pool1), 300_000_000 * USD));  // 30%
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 * USD));  // 60%

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

        uint256 CONST_POOL_VALUE = pool1.principalOut() + IERC20(USDC).balanceOf(pool1.liquidityLocker());

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertConstFundLoan(pool1, address(loan),  address(dlFactory1), 100_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan),  address(dlFactory1), 100_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan),  address(dlFactory2), 200_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan),  address(dlFactory2), 200_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan2), address(dlFactory1),  50_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan2), address(dlFactory1),  50_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan2), address(dlFactory2), 150_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan2), address(dlFactory2), 150_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        }
        
        assertEq(pool1.principalOut(), 1_000_000_000 * USD);
        assertEq(IERC20(USDC).balanceOf(pool1.liquidityLocker()), 0);

        DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));  // debtLocker1 = DebtLocker 1, for loan using dlFactory1
        DebtLocker debtLocker2 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2 = DebtLocker 2, for loan using dlFactory2
        DebtLocker debtLocker3 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory1)));  // debtLocker3 = DebtLocker 3, for loan2 using dlFactory1
        DebtLocker debtLocker4 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4 = DebtLocker 4, for loan2 using dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(loan),  cReq1);
            fay.approve(WETH, address(loan2), cReq2);
            eli.drawdown(address(loan),  100_000_000 * USD);
            fay.drawdown(address(loan2), 100_000_000 * USD);
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // USDC required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amtf_1);
            mint("USDC", address(fay), amtf_2);
            eli.approve(USDC, address(loan),  amtf_1);
            fay.approve(USDC, address(loan2), amtf_2);
            eli.makeFullPayment(address(loan));
            fay.makeFullPayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
        {      
            assertConstClaim(pool1, address(loan),  address(dlFactory1), IERC20(USDC), CONST_POOL_VALUE);
            assertConstClaim(pool1, address(loan),  address(dlFactory2), IERC20(USDC), CONST_POOL_VALUE);
            assertConstClaim(pool1, address(loan2), address(dlFactory1), IERC20(USDC), CONST_POOL_VALUE);
            assertConstClaim(pool1, address(loan2), address(dlFactory2), IERC20(USDC), CONST_POOL_VALUE);
        }
        
        assertTrue(pool1.principalOut() < 10);
    }

    function test_claim_singleLP() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            sid.approve(address(bPool), pool1.stakeLocker(), MAX_UINT);
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

            sid.finalize(address(pool1));
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("USDC", address(bob), 1_000_000_000 * USD);
            mint("USDC", address(che), 1_000_000_000 * USD);
            mint("USDC", address(dan), 1_000_000_000 * USD);

            bob.approve(USDC, address(pool1), MAX_UINT);
            che.approve(USDC, address(pool1), MAX_UINT);
            dan.approve(USDC, address(pool1), MAX_UINT);

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 * USD));  // 10%
            assertTrue(che.try_deposit(address(pool1), 300_000_000 * USD));  // 30%
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 * USD));  // 60%

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 200_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 200_000_000 * USD));

            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory1),  50_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory1),  50_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 150_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 150_000_000 * USD));
        }

        assertEq(pool1.principalOut(), 1_000_000_000 * USD);
        assertEq(IERC20(USDC).balanceOf(pool1.liquidityLocker()), 0);

        DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));  // debtLocker1 = DebtLocker 1, for loan using dlFactory1
        DebtLocker debtLocker2 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2 = DebtLocker 2, for loan using dlFactory2
        DebtLocker debtLocker3 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory1)));  // debtLocker3 = DebtLocker 3, for loan2 using dlFactory1
        DebtLocker debtLocker4 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4 = DebtLocker 4, for loan2 using dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(loan),  cReq1);
            fay.approve(WETH, address(loan2), cReq2);
            eli.drawdown(address(loan),  100_000_000 * USD);
            fay.drawdown(address(loan2), 100_000_000 * USD);
        }
        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        {
            (uint amt1_1,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            (uint amt1_2,,,) = loan2.getNextPayment(); // USDC required for 1st payment on loan2
            mint("USDC", address(eli), amt1_1);
            mint("USDC", address(fay), amt1_2);
            eli.approve(USDC, address(loan),  amt1_1);
            fay.approve(USDC, address(loan2), amt1_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
        {      
            checkClaim(debtLocker1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        {
            (uint amt2_1,,,) =  loan.getNextPayment(); // USDC required for 2nd payment on loan
            (uint amt2_2,,,) = loan2.getNextPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amt2_1);
            mint("USDC", address(fay), amt2_2);
            eli.approve(USDC, address(loan),  amt2_1);
            fay.approve(USDC, address(loan2), amt2_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));

            (uint amt3_1,,,) =  loan.getNextPayment(); // USDC required for 3rd payment on loan
            (uint amt3_2,,,) = loan2.getNextPayment(); // USDC required for 3rd payment on loan2
            mint("USDC", address(eli), amt3_1);
            mint("USDC", address(fay), amt3_2);
            eli.approve(USDC, address(loan),  amt3_1);
            fay.approve(USDC, address(loan2), amt3_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
        {      
            checkClaim(debtLocker1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // USDC required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amtf_1);
            mint("USDC", address(fay), amtf_2);
            eli.approve(USDC, address(loan),  amtf_1);
            fay.approve(USDC, address(loan2), amtf_2);
            eli.makeFullPayment(address(loan));
            fay.makeFullPayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
        {      
            checkClaim(debtLocker1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }

        assertTrue(pool1.principalOut() < 10);
    }
}
