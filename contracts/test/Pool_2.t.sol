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
    
    function test_claim_multipleLP() public {

        /******************************************/
        /*** Stake & Finalize 2 Liquidity Pools ***/
        /******************************************/
        address stakeLocker1 = pool1.stakeLocker();
        address stakeLocker2 = pool2.stakeLocker();
        {
            sid.approve(address(bPool), stakeLocker1, MAX_UINT);
            joe.approve(address(bPool), stakeLocker2, MAX_UINT);
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);
            joe.stake(pool2.stakeLocker(), bPool.balanceOf(address(joe)) / 2);
            sid.finalize(address(pool1));
            joe.finalize(address(pool2));
        }
       
        address liqLocker1 = pool1.liquidityLocker();
        address liqLocker2 = pool2.liquidityLocker();

        /*************************************************************/
        /*** Mint and deposit funds into liquidity pools (1b each) ***/
        /*************************************************************/
        {
            mint("USDC", address(bob), 1_000_000_000 * USD);
            mint("USDC", address(che), 1_000_000_000 * USD);
            mint("USDC", address(dan), 1_000_000_000 * USD);

            bob.approve(USDC, address(pool1), MAX_UINT);
            che.approve(USDC, address(pool1), MAX_UINT);
            dan.approve(USDC, address(pool1), MAX_UINT);

            bob.approve(USDC, address(pool2), MAX_UINT);
            che.approve(USDC, address(pool2), MAX_UINT);
            dan.approve(USDC, address(pool2), MAX_UINT);

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 * USD));  // 10% BOB in LP1
            assertTrue(che.try_deposit(address(pool1), 300_000_000 * USD));  // 30% CHE in LP1
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 * USD));  // 60% DAN in LP1

            assertTrue(bob.try_deposit(address(pool2), 500_000_000 * USD));  // 50% BOB in LP2
            assertTrue(che.try_deposit(address(pool2), 400_000_000 * USD));  // 40% BOB in LP2
            assertTrue(dan.try_deposit(address(pool2), 100_000_000 * USD));  // 10% BOB in LP2

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }
        
        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

        /***************************/
        /*** Fund loan / loan2 ***/
        /***************************/
        {
            // LP 1 Vault 1
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 25_000_000 * USD));  // Fund loan using dlFactory1 for 25m USDC
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 25_000_000 * USD));  // Fund loan using dlFactory1 for 25m USDC, again, 50m USDC total
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 25_000_000 * USD));  // Fund loan using dlFactory2 for 25m USDC
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 25_000_000 * USD));  // Fund loan using dlFactory2 for 25m USDC (no excess), 100m USDC total

            // LP 2 Vault 1
            assertTrue(joe.try_fundLoan(address(pool2), address(loan),  address(dlFactory1), 50_000_000 * USD));  // Fund loan using dlFactory1 for 50m USDC (excess), 150m USDC total
            assertTrue(joe.try_fundLoan(address(pool2), address(loan),  address(dlFactory2), 50_000_000 * USD));  // Fund loan using dlFactory2 for 50m USDC (excess), 200m USDC total

            // LP 1 Vault 2
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory1), 50_000_000 * USD));  // Fund loan2 using dlFactory1 for 50m USDC
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory1), 50_000_000 * USD));  // Fund loan2 using dlFactory1 for 50m USDC, again, 100m USDC total
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory2), 50_000_000 * USD));  // Fund loan2 using dlFactory2 for 50m USDC
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory2), 50_000_000 * USD));  // Fund loan2 using dlFactory2 for 50m USDC again, 200m USDC total

            // LP 2 Vault 2
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory1), 100_000_000 * USD));  // Fund loan2 using dlFactory1 for 100m USDC
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory1), 100_000_000 * USD));  // Fund loan2 using dlFactory1 for 100m USDC, again, 400m USDC total
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory2), 100_000_000 * USD));  // Fund loan2 using dlFactory2 for 100m USDC (excess)
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory2), 100_000_000 * USD));  // Fund loan2 using dlFactory2 for 100m USDC (excess), 600m USDC total
        }
        
        DebtLocker debtLocker1_pool1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));  // debtLocker1_pool1 = DebtLocker 1, for pool1, for loan using dlFactory1
        DebtLocker debtLocker2_pool1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2_pool1 = DebtLocker 2, for pool1, for loan using dlFactory2
        DebtLocker debtLocker3_pool1 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory1)));  // debtLocker3_pool1 = DebtLocker 3, for pool1, for loan2 using dlFactory1
        DebtLocker debtLocker4_pool1 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4_pool1 = DebtLocker 4, for pool1, for loan2 using dlFactory2
        DebtLocker debtLocker1_pool2 = DebtLocker(pool2.debtLockers(address(loan),  address(dlFactory1)));  // debtLocker1_pool2 = DebtLocker 1, for pool2, for loan using dlFactory1
        DebtLocker debtLocker2_pool2 = DebtLocker(pool2.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2_pool2 = DebtLocker 2, for pool2, for loan using dlFactory2
        DebtLocker debtLocker3_pool2 = DebtLocker(pool2.debtLockers(address(loan2), address(dlFactory1)));  // debtLocker3_pool2 = DebtLocker 3, for pool2, for loan2 using dlFactory1
        DebtLocker debtLocker4_pool2 = DebtLocker(pool2.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4_pool2 = DebtLocker 4, for pool2, for loan2 using dlFactory2

        // Present state checks
        assertEq(IERC20(USDC).balanceOf(liqLocker1),              700_000_000 * USD);  // 1b USDC deposited - (100m USDC - 200m USDC)
        assertEq(IERC20(USDC).balanceOf(liqLocker2),              500_000_000 * USD);  // 1b USDC deposited - (100m USDC - 400m USDC)
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),  200_000_000 * USD);  // Balance of loan fl 
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker2)), 600_000_000 * USD);  // Balance of loan2 fl (no excess, exactly 400 USDC from LP1 & 600 USDC from LP2)
        assertEq(loan.balanceOf(address(debtLocker1_pool1)),       50_000_000 ether);  // Balance of debtLocker1 for pool1 with dlFactory1
        assertEq(loan.balanceOf(address(debtLocker2_pool1)),       50_000_000 ether);  // Balance of debtLocker2 for pool1 with dlFactory2
        assertEq(loan2.balanceOf(address(debtLocker3_pool1)),     100_000_000 ether);  // Balance of debtLocker3 for pool1 with dlFactory1
        assertEq(loan2.balanceOf(address(debtLocker4_pool1)),     100_000_000 ether);  // Balance of debtLocker4 for pool1 with dlFactory2
        assertEq(loan.balanceOf(address(debtLocker1_pool2)),       50_000_000 ether);  // Balance of debtLocker1 for pool2 with dlFactory1
        assertEq(loan.balanceOf(address(debtLocker2_pool2)),       50_000_000 ether);  // Balance of debtLocker2 for pool2 with dlFactory2
        assertEq(loan2.balanceOf(address(debtLocker3_pool2)),     200_000_000 ether);  // Balance of debtLocker3 for pool2 with dlFactory1
        assertEq(loan2.balanceOf(address(debtLocker4_pool2)),     200_000_000 ether);  // Balance of debtLocker4 for pool2 with dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(500_000_000 * USD); // wETH required for 500m USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(400_000_000 * USD); // wETH required for 500m USDC drawdown on loan2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(loan),  cReq1);
            fay.approve(WETH, address(loan2), cReq2);
            eli.drawdown(address(loan),  100_000_000 * USD); // 100m excess to be returned
            fay.drawdown(address(loan2), 300_000_000 * USD); // 200m excess to be returned
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
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        {
            checkClaim(debtLocker1_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker2_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker4_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory2));
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

        /*****************/
        /***  LP Claim ***/
        /*****************/
        {
            checkClaim(debtLocker1_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker2_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker4_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory2));
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
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        {
            checkClaim(debtLocker1_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker2_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker4_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }

        assertTrue(pool1.principalOut() < 10);
        assertTrue(pool2.principalOut() < 10);
    }

    function test_claim_external_transfers() public {
        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            sid.approve(address(bPool), pool1.stakeLocker(), uint(-1));
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

            sid.finalize(address(pool1));

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        /**********************************************************/
        /*** Mint, deposit funds into liquidity pool, fund loan ***/
        /**********************************************************/
        {
            mint("USDC", address(bob), 1_000_000_000 * USD);
            bob.approve(USDC, address(pool1), uint(-1));
            bob.approve(USDC, address(this),  uint(-1));
            bob.deposit(address(pool1), 100_000_000 * USD);
            sid.fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 * USD);
            assertEq(pool1.principalOut(), 100_000_000 * USD);
        }

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            mint("WETH", address(eli), cReq1);
            eli.approve(WETH, address(loan),  cReq1);
            eli.drawdown(address(loan),  100_000_000 * USD);
        }

        /*****************************/
        /*** Make Interest Payment ***/
        /*****************************/
        {
            (uint amt,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            mint("USDC", address(eli), amt);
            eli.approve(USDC, address(loan),  amt);
            eli.makePayment(address(loan));
        }

        /**********************************************/
        /*** Transfer USDC into Pool and debtLocker ***/
        /**********************************************/
        {
            DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));

            uint256 poolBal_before       = IERC20(USDC).balanceOf(address(pool1));
            uint256 debtLockerBal_before = IERC20(USDC).balanceOf(address(debtLocker1));

            IERC20(USDC).transferFrom(address(bob), address(pool1),       1000 * USD);
            IERC20(USDC).transferFrom(address(bob), address(debtLocker1), 2000 * USD);

            uint256 poolBal_after       = IERC20(USDC).balanceOf(address(pool1));
            uint256 debtLockerBal_after = IERC20(USDC).balanceOf(address(debtLocker1));

            assertEq(poolBal_after - poolBal_before,             1000 * USD);
            assertEq(debtLockerBal_after - debtLockerBal_before, 2000 * USD);

            poolBal_before       = poolBal_after;
            debtLockerBal_before = debtLockerBal_after;

            checkClaim(debtLocker1, loan, sid, IERC20(USDC), pool1, address(dlFactory1));

            poolBal_after       = IERC20(USDC).balanceOf(address(pool1));
            debtLockerBal_after = IERC20(USDC).balanceOf(address(debtLocker1));

            assertTrue(poolBal_after - poolBal_before < 10);  // Collects some rounding dust
            assertEq(debtLockerBal_after, debtLockerBal_before);
        }

        /*************************/
        /*** Make Full Payment ***/
        /*************************/
        {
            (uint amt,,) =  loan.getFullPayment(); // USDC required for 1st payment on loan
            mint("USDC", address(eli), amt);
            eli.approve(USDC, address(loan),  amt);
            eli.makeFullPayment(address(loan));
        }

        /*********************************************************/
        /*** Check claim with existing balances in DL and Pool ***/
        /*********************************************************/
        {
            DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));

            uint256 poolBal_before       = IERC20(USDC).balanceOf(address(pool1));
            uint256 debtLockerBal_before = IERC20(USDC).balanceOf(address(debtLocker1));

            checkClaim(debtLocker1, loan, sid, IERC20(USDC), pool1, address(dlFactory1));

            uint256 poolBal_after       = IERC20(USDC).balanceOf(address(pool1));
            uint256 debtLockerBal_after = IERC20(USDC).balanceOf(address(debtLocker1));

            assertTrue(poolBal_after - poolBal_before < 10);  // Collects some rounding dust
            assertEq(debtLockerBal_after, debtLockerBal_before);
        }

        assertTrue(pool1.principalOut() < 10);
    }

    function setUpWithdraw() internal {
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
            sid.claim(address(pool1), address(loan),  address(dlFactory1));
            sid.claim(address(pool1), address(loan),  address(dlFactory2));
            sid.claim(address(pool1), address(loan2), address(dlFactory1));
            sid.claim(address(pool1), address(loan2), address(dlFactory2));
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
            sid.claim(address(pool1), address(loan),  address(dlFactory1));
            sid.claim(address(pool1), address(loan),  address(dlFactory2));
            sid.claim(address(pool1), address(loan2), address(dlFactory1));
            sid.claim(address(pool1), address(loan2), address(dlFactory2));
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
            sid.claim(address(pool1), address(loan),  address(dlFactory1));
            sid.claim(address(pool1), address(loan),  address(dlFactory2));
            sid.claim(address(pool1), address(loan2), address(dlFactory1));
            sid.claim(address(pool1), address(loan2), address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }
    }
    
    function test_withdraw_calculator() public {

        setUpWithdraw();

        uint256 start = block.timestamp;
        uint256 delay = pool1.penaltyDelay();
        uint256 lockup = pool1.lockupPeriod();

        assertEq(pool1.calcWithdrawPenalty(1 * USD, address(bob)), uint256(0));  // Returns 0 when lockupPeriod > penaltyDelay.
        assertTrue(!joe.try_setLockupPeriod(address(pool1), 15 days));
        assertEq(pool1.lockupPeriod(), 90 days);
        assertTrue(sid.try_setLockupPeriod(address(pool1), 15 days));
        assertEq(pool1.lockupPeriod(), 15 days);

        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 1 ether);  // 100% of (interest + penalty) is subtracted on immediate withdrawal

        hevm.warp(start + delay / 3);
        withinPrecision(pool1.calcWithdrawPenalty(1 ether, address(bob)), uint(2 ether) / 3, 6); // After 1/3 delay has passed, 2/3 (interest + penalty) is subtracted

        hevm.warp(start + delay / 2);
        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 0.5 ether);  // After half delay has passed, 1/2 (interest + penalty) is subtracted

        hevm.warp(start + delay - 1);
        assertTrue(pool1.calcWithdrawPenalty(1 ether, address(bob)) > 0); // Still a penalty
        
        hevm.warp(start + delay);
        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 0); // After delay has passed, no penalty

        hevm.warp(start + delay + 1);
        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 0); 

        hevm.warp(start + delay * 2);
        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 0);

        hevm.warp(start + delay * 1000);
        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 0);
    }

    function test_withdraw_under_lockup_period() public {
        setUpWithdraw();
        uint start = block.timestamp;

        // Mint USDC to kim
        mint("USDC", address(kim), 5000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));
        
        // Deposit 1000 USDC and check depositDate
        assertTrue(kim.try_deposit(address(pool1), 1000 * USD));
        assertEq(pool1.depositDate(address(kim)), start);

        // Fund loan, drawdown, make payment and claim so kim can claim interest
        assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1000 * USD), "Fail to fund the loan");
        _drawDownLoan(1000 * USD, loan3, hal);
        _makeLoanPayment(loan3, hal); 
        sid.claim(address(pool1), address(loan3), address(dlFactory1));
        assertEq(pool1.calcWithdrawPenalty(1000 * USD, address(kim)), uint256(0)); // lockupPeriod > withdrawDelay

        uint256 interest = pool1.withdrawableFundsOf(address(kim));  // Get kims withdrawable funds

        // Warp to exact time that kim can withdraw with weighted deposit date
        hevm.warp(pool1.depositDate(address(kim)) + pool1.lockupPeriod() - 1);
        assertTrue(!kim.try_withdraw(address(pool1), 1000 * USD), "Withdraw failure didn't trigger");
        hevm.warp(pool1.depositDate(address(kim)) + pool1.lockupPeriod());
        assertTrue( kim.try_withdraw(address(pool1), 1000 * USD), "Failed to withdraw funds");

        assertEq(IERC20(USDC).balanceOf(address(kim)) - bal0, interest);
    }

    function test_withdraw_under_weighted_lockup_period() public {
        setUpWithdraw();
        uint start = block.timestamp;

        // Mint USDC to kim
        mint("USDC", address(kim), 5000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));

        // Deposit 1000 USDC and check depositDate
        assertTrue(kim.try_deposit(address(pool1), 1000 * USD));
        assertEq(pool1.depositDate(address(kim)), start);

        // Fund loan, drawdown, make payment and claim so kim can claim interest
        assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1000 * USD), "Fail to fund the loan");
        _drawDownLoan(1000 * USD, loan3, hal);
        _makeLoanPayment(loan3, hal); 
        sid.claim(address(pool1), address(loan3), address(dlFactory1));
        assertEq(pool1.calcWithdrawPenalty(1000 * USD, address(kim)), uint256(0)); // lockupPeriod > withdrawDelay

        // Warp to exact time that kim can withdraw for the first time
        hevm.warp(start + pool1.lockupPeriod());  
        assertEq(block.timestamp - pool1.depositDate(address(kim)), pool1.lockupPeriod());  // Can withdraw at this point
        
        // Deposit more USDC into pool, increasing deposit date and locking up funds again
        assertTrue(kim.try_deposit(address(pool1), 3000 * USD));
        assertEq(pool1.depositDate(address(kim)) - start, (block.timestamp - start) * (3000 * WAD) / (4000 * WAD));  // Deposit date updating using weighting
        assertTrue(!kim.try_withdraw(address(pool1), 4000 * USD), "Withdraw failure didn't trigger");                // Not able to withdraw the funds as deposit date was updated

        uint256 interest = pool1.withdrawableFundsOf(address(kim));  // Get kims withdrawable funds

        // Warp to exact time that kim can withdraw with weighted deposit date
        hevm.warp(pool1.depositDate(address(kim)) + pool1.lockupPeriod() - 1);
        assertTrue(!kim.try_withdraw(address(pool1), 4000 * USD), "Withdraw failure didn't trigger");
        hevm.warp(pool1.depositDate(address(kim)) + pool1.lockupPeriod());
        assertTrue( kim.try_withdraw(address(pool1), 4000 * USD), "Failed to withdraw funds");

        assertEq(IERC20(USDC).balanceOf(address(kim)) - bal0, interest);
    }

    function test_withdraw_no_principal_penalty() public {
        setUpWithdraw();
        
        uint start = block.timestamp;

        sid.setPrincipalPenalty(address(pool1), 0);
        assertTrue(sid.try_setLockupPeriod(address(pool1), 0));
        assertEq(pool1.lockupPeriod(), uint256(0));

        mint("USDC", address(kim), 2000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        assertTrue(kim.try_deposit(address(pool1), 1000 * USD));
        
        (uint total_kim, uint principal_kim, uint interest_kim) = pool1.claimableFunds(address(kim));

        assertEq(total_kim,     1000 * USD);
        assertEq(principal_kim, 1000 * USD);
        assertEq(interest_kim,           0);

        uint256 withdrawAmount = 1000 * USD;
        kim.withdraw(address(pool1), withdrawAmount);

        assertEq(IERC20(USDC).balanceOf(address(kim)), 2000 * USD);
        
        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));

        assertTrue(kim.try_deposit(address(pool1), 1000 * USD), "Fail to deposit liquidity");                                      // Add another 1000 USDC.
        assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1000 * USD), "Fail to fund the loan");   // Fund the loan.
        hevm.warp(start + pool1.penaltyDelay());                                                                                   // Fast-forward to claim all proportionate interest.
        _drawDownLoan(1000 * USD, loan3, hal);                                                                                     // Draw down the loan.
        _makeLoanPayment(loan3, hal);                                                                                              // Make loan payment.
        sid.claim(address(pool1), address(loan3), address(dlFactory1));                                                            // Fund claimed by the pool.

        uint256 interest = pool1.withdrawableFundsOf(address(kim));

        kim.withdraw(address(pool1), withdrawAmount);
        uint256 bal1 = IERC20(USDC).balanceOf(address(kim));

        assertEq(bal1 - bal0, interest);
    }

    function test_withdraw_principal_penalty() public {
        setUpWithdraw();

        uint start = block.timestamp;
        
        sid.setPrincipalPenalty(address(pool1), 500);
        assertTrue(sid.try_setLockupPeriod(address(pool1), 0));
        assertEq(pool1.lockupPeriod(), uint256(0));

        mint("USDC", address(kim), 2000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);

        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));
        uint256 depositAmount = 1000 * USD;
        uint256 lpToken       = 1000 * WAD;
        assertTrue(kim.try_deposit(address(pool1), depositAmount));  // Deposit and withdraw in same tx
        
        (uint total_kim, uint principal_kim, uint interest_kim) = pool1.claimableFunds(address(kim));

        assertEq(total_kim,     950 * USD);
        assertEq(principal_kim, 950 * USD);
        assertEq(interest_kim,          0);

        kim.withdraw(address(pool1), depositAmount);
        uint256 bal1 = IERC20(USDC).balanceOf(address(kim));  // Balance after principal penalty

        assertEq(bal0 - bal1, 50 * USD); // 5% principal penalty.
    }

    function test_withdraw_principal_and_interest_penalty() public {
        setUpWithdraw();

        uint start = block.timestamp;
        
        sid.setPrincipalPenalty(address(pool1), 500);
        assertTrue(sid.try_setLockupPeriod(address(pool1), 0));
        assertEq(pool1.lockupPeriod(), uint256(0));

        mint("USDC", address(kim), 2000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        
        // Do another deposit with same amount
        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));  // Get balance before deposit
        uint256 depositAmount = 1000 * USD;
        uint256 lpToken       = 1000 * WAD;
        uint256 beforeTotalSupply = pool1.totalSupply();

        {
            uint256 beforeLLBalance = IERC20(USDC).balanceOf(pool1.liquidityLocker());

            assertTrue(kim.try_deposit(address(pool1),  depositAmount));                                                           // Add another 1000 USDC.
            assertEq(pool1.balanceOf(address(kim)),     lpToken, "Failed to update LP balance");                                   // Verify the LP token balance.
            assertEq(pool1.totalSupply(),               beforeTotalSupply.add(lpToken), "Failed to update the TS");                // Pool total supply get increase by the lpToken.
            assertEq(_getLLBal(pool1),                  beforeLLBalance.add(depositAmount), "Failed to update the LL balance");    // Make sure liquidity locker balance get increases.

            assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1000 * USD), "Fail to fund the loan");  // Fund the loan.
            assertEq(_getLLBal(pool1),                  beforeLLBalance, "Failed to update the LL balance");                          // Make sure liquidity locker balance get increases.

            _drawDownLoan(1000 * USD, loan3, hal);                             // Draw down the loan.
            hevm.warp(start + pool1.penaltyDelay() - 10 days);                 // Fast-forward to claim all proportionate interest, taking a penalty
            _makeLoanPayment(loan3, hal);                                      // Make loan payment.
            sid.claim(address(pool1), address(loan3), address(dlFactory1));    // Fund claimed by the pool
        }

        {
            uint256 interest       = pool1.withdrawableFundsOf(address(kim));
            uint256 priPenalty     = pool1.principalPenalty().mul(depositAmount).div(10000);             // Calculate flat principal penalty.
            uint256 totPenalty     = pool1.calcWithdrawPenalty(interest.add(priPenalty), address(kim));  // Get total penalty
            uint256 oldInterestSum = pool1.interestSum();
            
            (uint256 total_kim, uint256 principal_kim, uint256 interest_kim) = pool1.claimableFunds(address(kim));
            uint256 bal1 = IERC20(USDC).balanceOf(address(kim));  // Get balance before withdraw

            kim.withdraw(address(pool1), depositAmount);

            uint256 bal2 = IERC20(USDC).balanceOf(address(kim));                                          // Get balance after withdraw
            uint256 balanceDiff = bal2 > bal0 ? bal2 - bal0 : bal0 - bal2;                                // Get balance difference between before deposit and after withdraw
            uint256 extraAmount = totPenalty > interest ? totPenalty - interest : interest - totPenalty;  // Get amount from interest/pentalty

            assertEq(total_kim, bal2 - bal1);
            assertTrue(totPenalty != uint256(0));
            withinPrecision(balanceDiff, extraAmount, 6);                                                                        // All of principal returned, plus interest
            assertEq(pool1.balanceOf(address(kim)),                 0,                    "Failed to burn the tokens");          // LP tokens get burned.
            assertEq(pool1.totalSupply(),                           beforeTotalSupply,    "Failed to decrement the supply");     // Supply get reset.
            assertEq(oldInterestSum.sub(interest).add(totPenalty),  pool1.interestSum(),  "Failed to update the interest sum");  // Interest sum is increased by totPenalty and decreased by the entitled interest.
        }
    }

    function test_setPenaltyDelay() public {
        assertEq(pool1.penaltyDelay(),                      30 days);
        assertTrue(!joe.try_setPenaltyDelay(address(pool1), 45 days));
        assertTrue( sid.try_setPenaltyDelay(address(pool1), 45 days));
        assertEq(pool1.penaltyDelay(),                      45 days);
    }

    function test_setPrincipalPenalty() public {
        assertEq(pool1.principalPenalty(),                      500);
        assertTrue(!joe.try_setPrincipalPenalty(address(pool1), 1125));
        assertTrue( sid.try_setPrincipalPenalty(address(pool1), 1125));
        assertEq(pool1.principalPenalty(),                      1125);
    }

    function _makeLoanPayment(Loan loan, Borrower by) internal {
        (uint amt,,,) =  loan.getNextPayment();
        mint("USDC", address(by), amt);
        by.approve(USDC, address(loan),  amt);
        by.makePayment(address(loan));
    }

    function _drawDownLoan(uint256 drawDownAmount, Loan loan, Borrower by) internal  {
        uint cReq =  loan.collateralRequiredForDrawdown(drawDownAmount);
        mint("WETH", address(by), cReq);
        by.approve(WETH, address(loan),  cReq);
        by.drawdown(address(loan),  drawDownAmount);
    }

    function _getLLBal(Pool who) internal returns(uint256) {
        return IERC20(USDC).balanceOf(who.liquidityLocker());
    }

    function test_deactivate() public {

        setUpWithdraw();

        address liquidityAsset = address(pool1.liquidityAsset());
        uint liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool1.principalOut() <= 100 * 10 ** liquidityAssetDecimals);

        sid.deactivate(address(pool1), 86);

        // Post-state checks.
        assertEq(int(pool1.poolState()), 2);

        // Deactivation should block the following functionality:

        // deposit()
        mint("USDC", address(bob), 1_000_000_000 * USD);
        bob.approve(USDC, address(pool1), uint(-1));
        assertTrue(!bob.try_deposit(address(pool1), 100_000_000 * USD));

        // fundLoan()
        assertTrue(!sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 1));

        // deactivate()
        assertTrue(!sid.try_deactivate(address(pool1)));

    }

    function test_deactivate_fail() public {

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

        address liquidityAsset = address(pool1.liquidityAsset());
        uint liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool1.principalOut() >= 100 * 10 ** liquidityAssetDecimals);
        assertTrue(!sid.try_deactivate(address(pool1)));

    }

    function test_view_balance() public {
        setUpWithdraw();

        uint start = block.timestamp;

        // Mint and deposit 1000 USDC
        mint("USDC", address(kim), 1_000_000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));
        assertTrue(kim.try_deposit(address(pool1), 1_000_000 * USD));

        // Fund loan, drawdown, make payment and claim so kim can claim interest
        assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1_000_000 * USD), "Fail to fund the loan");
        _drawDownLoan(1_000_000 * USD, loan3, hal);
        _makeLoanPayment(loan3, hal); 
        sid.claim(address(pool1), address(loan3), address(dlFactory1));

        uint withdrawDate = pool1.depositDate(address(kim)).add(pool1.lockupPeriod());

        hevm.warp(withdrawDate - 1);
        (uint total_kim, uint principal_kim, uint interest_kim) = pool1.claimableFunds(address(kim));

        // Deposit is still in lock-up
        assertEq(principal_kim, 0);
        assertEq(interest_kim, pool1.withdrawableFundsOf(address(kim)));
        assertEq(total_kim, principal_kim + interest_kim);

        hevm.warp(withdrawDate);
        (total_kim, principal_kim, interest_kim) = pool1.claimableFunds(address(kim));

        assertGt(principal_kim, 0);
        assertGt(interest_kim, 0);
        assertGt(total_kim, 0);
        assertEq(total_kim, principal_kim + interest_kim);

        uint256 kim_bal_pre = IERC20(pool1.liquidityAsset()).balanceOf(address(kim));
        
        assertTrue(kim.try_withdraw(address(pool1), principal_kim), "Failed to withdraw claimable_kim");
        
        uint256 kim_bal_post = IERC20(pool1.liquidityAsset()).balanceOf(address(kim));

        assertEq(kim_bal_post - kim_bal_pre, principal_kim + interest_kim);

    }
}
