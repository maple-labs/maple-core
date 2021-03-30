// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/LP.sol";
import "./user/PoolDelegate.sol";

import "../interfaces/IBFactory.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IStakeLocker.sol";

import "../RepaymentCalc.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

interface IBPoolFactory {
    function newBPool() external returns (address);
}

contract Treasury { }

contract CalcsTest is TestUtil {

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

    RepaymentCalc                repaymentCalc;
    CollateralLockerFactory          clFactory;
    DebtLockerFactory               dlFactory1;
    DebtLockerFactory               dlFactory2;
    FundingLockerFactory             flFactory;
    LateFeeCalc                    lateFeeCalc;
    LiquidityLockerFactory           llFactory;
    Loan                                  loan;
    Loan                                 loan2;
    Loan                                 loan3;
    LoanFactory                    loanFactory;
    MapleGlobals                       globals;
    MapleToken                             mpl;
    PoolFactory                    poolFactory;
    Pool                                 pool1;
    Pool                                 pool2;
    PremiumCalc                    premiumCalc;
    StakeLockerFactory               slFactory;
    Treasury                               trs;
    ChainlinkOracle                 wethOracle;
    ChainlinkOracle                 wbtcOracle;
    UsdOracle                        usdOracle;
    
    ERC20                           fundsToken;
    IBPool                               bPool;

    uint256 constant public MAX_UINT = uint(-1);

    function setUp() public {

        eli            = new Borrower();                                                // Actor: Borrower of the Loan.
        fay            = new Borrower();                                                // Actor: Borrower of the Loan.
        hal            = new Borrower();                                                // Actor: Borrower of the Loan.
        gov            = new Governor();                                                // Actor: Governor of Maple.
        bob            = new LP();                                                      // Actor: Liquidity provider.
        che            = new LP();                                                      // Actor: Liquidity provider.
        dan            = new LP();                                                      // Actor: Liquidity provider.
        kim            = new LP();                                                      // Actor: Liquidity provider.
        sid            = new PoolDelegate();                                            // Actor: Manager of the Pool.
        joe            = new PoolDelegate();                                            // Actor: Manager of the Pool.

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
        repaymentCalc  = new RepaymentCalc();                                           // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                                            // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);                                          // Flat 5% premium
        trs            = new Treasury();                                                // Treasury.

        gov.setValidPoolFactory(address(poolFactory), true);
        gov.setValidLoanFactory(address(loanFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory),  true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory),  true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory1), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory2), true);

        wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        usdOracle  = new UsdOracle();
        
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));

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

        gov.setPoolDelegateAllowlist(address(sid), true);
        gov.setPoolDelegateAllowlist(address(joe), true);
        gov.setMapleTreasury(address(trs));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), bPool.balanceOf(address(this)) / 2);
        bPool.transfer(address(joe), bPool.balanceOf(address(this)));

        // Set Globals
        gov.setCalc(address(repaymentCalc),  true);
        gov.setCalc(address(lateFeeCalc), true);
        gov.setCalc(address(premiumCalc), true);
        gov.setCollateralAsset(WETH, true);
        gov.setLoanAsset(USDC, true);
        gov.setSwapOutRequired(1_000_000);

        // Create and finalize Liquidity Pool
        pool1 = Pool(sid.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            uint256(-1)
        ));
        sid.approve(address(bPool), pool1.stakeLocker(), uint(-1));
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        sid.finalize(address(pool1)); 
        sid.setOpenToPublic(address(pool1), true);
    }

    function setUpRepayments(uint256 loanAmt, uint256 apr, uint16 index, uint16 numPayments, uint256 lateFee, uint256 premiumFee) public {
        {
            repaymentCalc = new RepaymentCalc();         // Repayment
            lateFeeCalc   = new LateFeeCalc(lateFee);    // Flat late fee
            premiumCalc   = new PremiumCalc(premiumFee); // Flat premium

            gov.setCalc(address(repaymentCalc),  true);
            gov.setCalc(address(lateFeeCalc), true);
            gov.setCalc(address(premiumCalc), true);
        }

        uint16[10] memory paymentIntervalArray = [1, 2, 5, 7, 10, 15, 30, 60, 90, 360];

        uint256 paymentInterval = paymentIntervalArray[index % 10];
        uint256 termDays        = paymentInterval * (numPayments % 100);

        {
            // Mint "infinite" amount of USDC and deposit into pool
            mint("USDC", address(this), loanAmt);
            IERC20(USDC).approve(address(pool1), uint(-1));
            pool1.deposit(loanAmt);

            // Create loan, fund loan, draw down on loan
            address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];
            uint256[6] memory specs = [apr, termDays, paymentInterval, loanAmt, 2000, 7];
            loan = eli.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory),  specs, calcs);
        }

        assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), loanAmt));

        {
            uint cReq = loan.collateralRequiredForDrawdown(loanAmt); // wETH required for 1_000 USDC drawdown on loan
            mint("WETH", address(eli), cReq);
            eli.approve(WETH, address(loan), cReq);
            eli.drawdown(address(loan), loanAmt);
        }
    }

    function test_repayments(uint256 _loanAmt, uint16 apr, uint16 index, uint16 numPayments) public {
        uint256 loanAmt = constrictToRange(_loanAmt, 10_000 * USD, 100 * 1E9 * USD, true);  // $10k to $100b, non zero

        apr = apr % 10_000;

        setUpRepayments(loanAmt, uint256(apr), index, numPayments, 100, 100);
        
        // Calculate theoretical values and sum up actual values
        uint256 totalPaid;
        uint256 sumTotal;
        {
            uint256 paymentIntervalDays = loan.paymentIntervalSeconds().div(1 days);
            uint256 totalInterest       = loanAmt * apr / 10_000 * paymentIntervalDays / 365 * loan.paymentsRemaining();
                    totalPaid           = loanAmt + totalInterest;
        }

        (uint256 lastTotal,, uint256 lastInterest,,) = loan.getNextPayment();

        mint("USDC",      address(eli),  loanAmt * 1000); // Mint enough to pay interest
        eli.approve(USDC, address(loan), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(eli));

        while (loan.paymentsRemaining() > 0) {

            (uint256 total,      uint256 principal,      uint256 interest,,)    = loan.getNextPayment();                       // USDC required for payment on loan
            (uint256 total_calc, uint256 principal_calc, uint256 interest_calc) = repaymentCalc.getNextPayment(address(loan)); // USDC required for payment on loan

            assertEq(total,         total_calc);
            assertEq(principal, principal_calc);
            assertEq(interest,   interest_calc);

            sumTotal += total;

            eli.makePayment(address(loan)); 

            if (loan.paymentsRemaining() > 0) {
                assertEq(total,        lastTotal);
                assertEq(interest,  lastInterest);
                assertEq(total,         interest);
                assertEq(principal,            0);
            } else {
                assertEq(total,     principal + interest);
                assertEq(principal,              loanAmt);
                withinPrecision(totalPaid, sumTotal, 8);
                assertEq(beforeBal - IERC20(USDC).balanceOf(address(eli)), sumTotal); // Pays back all principal, plus interest
            }
            
            lastTotal    = total;
            lastInterest = interest;
        }
    }

    function test_late_fee(uint56 _loanAmt, uint256 apr, uint16 index, uint16 numPayments, uint256 lateFee) public {
        uint256 loanAmt = constrictToRange(_loanAmt, 10_000 * USD, 100 * 1E9 * USD, true);  // $10k to $100b, non zero

        apr     = apr     % 10_000;
        lateFee = lateFee % 10_000;

        setUpRepayments(loanAmt, apr, index, numPayments, lateFee, 100);
        
        // Calculate theoretical values and sum up actual values
        uint256 totalPaid;
        uint256 sumTotal;
        {
            uint256 paymentIntervalDays = loan.paymentIntervalSeconds().div(1 days);
            uint256 totalInterest       = loanAmt * apr / 10_000 * paymentIntervalDays / 365 * loan.paymentsRemaining();
                    totalPaid           = loanAmt + totalInterest + totalInterest * lateFeeCalc.feeBips() / 10_000;
        }

        hevm.warp(loan.nextPaymentDue() + 1);  // Payment is late
        (uint256 lastTotal,,,,) =  loan.getNextPayment();

        mint("USDC",      address(eli),  loanAmt * 1000); // Mint enough to pay interest
        eli.approve(USDC, address(loan), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(eli));

        while (loan.paymentsRemaining() > 0) {
            hevm.warp(loan.nextPaymentDue() + 1);  // Payment is late

            (uint256 total,      uint256 principal,      uint256 interest,,)    = loan.getNextPayment();                       // USDC required for payment on loan
            (uint256 total_calc, uint256 principal_calc, uint256 interest_calc) = repaymentCalc.getNextPayment(address(loan)); // USDC required for payment on loan
            (uint256 total_late, uint256 principal_late, uint256 interest_late) = lateFeeCalc.getLateFee(address(loan));       // USDC required for payment on loan

            assertEq(total,         total_calc +     total_late);
            assertEq(principal, principal_calc + principal_late);
            assertEq(interest,   interest_calc +  interest_late);

            sumTotal += total;
            
            eli.makePayment(address(loan));

            if (loan.paymentsRemaining() > 0) {
                assertEq(total,        lastTotal);
                assertEq(total,         interest);
                assertEq(principal,            0);

                assertEq(interest_late, total_calc * lateFeeCalc.feeBips() / 10_000);
                assertEq(interest_late, total_late);
                assertEq(principal_late, 0);
            } else {
                assertEq(total,     principal + interest);
                assertEq(principal,              loanAmt);
                withinPrecision(totalPaid, sumTotal, 8);
                assertEq(beforeBal - IERC20(USDC).balanceOf(address(eli)), sumTotal); // Pays back all principal, plus interest
            }
            
            lastTotal = total;
        }
    }

    function test_premium(uint56 _loanAmt, uint256 premiumFee) public {
        uint256 loanAmt = uint256(_loanAmt) + 10 ** 6;  // uint56(-1) = ~72b * 10 ** 6

        premiumFee = premiumFee % 10_000;

        setUpRepayments(loanAmt, 100, 1, 1, 100, premiumFee);

        mint("USDC",      address(eli),  loanAmt * 1000); // Mint enough to pay interest
        eli.approve(USDC, address(loan), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(eli));

        (uint256 total,         uint256 principal,         uint256 interest)         = loan.getFullPayment();                         // USDC required for payment on loan
        (uint256 total_premium, uint256 principal_premium, uint256 interest_premium) = premiumCalc.getPremiumPayment(address(loan));  // USDC required for payment on loan

        assertEq(total,         total_premium);
        assertEq(principal, principal_premium);
        assertEq(interest,   interest_premium);

        assertEq(interest, principal * premiumCalc.premiumBips() / 10_000);

        eli.makeFullPayment(address(loan));

        uint256 afterBal = IERC20(USDC).balanceOf(address(eli));
        
        assertEq(beforeBal - afterBal, total);
    }
}