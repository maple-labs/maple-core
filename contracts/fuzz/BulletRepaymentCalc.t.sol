// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "../test/TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";

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

    function claim(address pool, address loan, address dlFactory) external returns(uint256[7] memory) {
        return IPool(pool).claim(loan, dlFactory);  
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

contract BulletRepaymentCalcTest is TestUtil {

    using SafeMath for uint256;

    ERC20                           fundsToken;
    MapleToken                             mpl;
    MapleGlobals                       globals;
    FundingLockerFactory             flFactory;
    CollateralLockerFactory          clFactory;
    LoanFactory                    loanFactory;
    Loan                                  loan;
    Loan                                 loan2;
    PoolFactory                 poolFactory;
    StakeLockerFactory               slFactory;
    LiquidityLockerFactory         llFactory; 
    DebtLockerFactory               dlFactory1; 
    DebtLockerFactory               dlFactory2; 
    Pool                                 pool1; 
    Pool                                 pool2; 
    DSValue                          ethOracle;
    DSValue                         usdcOracle;
    BulletRepaymentCalc             bulletCalc;
    LateFeeCalc                    lateFeeCalc;
    PremiumCalc                    premiumCalc;
    IBPool                               bPool;
    PoolDelegate                           sid;
    PoolDelegate                           joe;
    LP                                     bob;
    LP                                     che;
    LP                                     dan;
    Borrower                               eli;
    Borrower                               fay;
    Treasury                               trs;


    function setUp() public {

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = new MapleGlobals(address(this), address(mpl), BPOOL_FACTORY);
        flFactory      = new FundingLockerFactory();
        clFactory      = new CollateralLockerFactory();
        loanFactory    = new LoanFactory(address(globals));
        slFactory      = new StakeLockerFactory();
        llFactory      = new LiquidityLockerFactory();
        poolFactory    = new PoolFactory(address(globals));
        dlFactory1     = new DebtLockerFactory();
        dlFactory2     = new DebtLockerFactory();
        ethOracle      = new DSValue();
        usdcOracle     = new DSValue();
        sid            = new PoolDelegate();
        joe            = new PoolDelegate();
        bob            = new LP();
        che            = new LP();
        dan            = new LP();
        eli            = new Borrower();
        fay            = new Borrower();
        trs            = new Treasury();

        globals.setValidLoanFactory(address(loanFactory), true);
        globals.setValidLoanFactory(address(poolFactory), true);

        globals.setValidSubFactory(address(loanFactory), address(flFactory), true);
        globals.setValidSubFactory(address(loanFactory), address(clFactory), true);

        globals.setValidSubFactory(address(poolFactory), address(llFactory), true);
        globals.setValidSubFactory(address(poolFactory), address(slFactory), true);

        ethOracle.poke(500 ether);  // Set ETH price to $500
        usdcOracle.poke(1 ether);   // Set USDC price to $1

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
        globals.setPoolDelegateWhitelist(address(joe), true);
        globals.setMapleTreasury(address(trs));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), bPool.balanceOf(address(this)) / 2);
        bPool.transfer(address(joe), bPool.balanceOf(address(this)));

        // Set Globals
        globals.setCalc(address(bulletCalc),  true);
        globals.setCalc(address(lateFeeCalc), true);
        globals.setCalc(address(premiumCalc), true);
        globals.setCollateralAsset(WETH, true);
        globals.setLoanAsset(USDC, true);
        globals.assignPriceFeed(WETH, address(ethOracle));
        globals.assignPriceFeed(USDC, address(usdcOracle));
        globals.setSwapOutRequired(100);

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

        pool1.finalize(); 
    }

    function setUpRepayments(uint256 loanAmt, uint256 apr, uint16 index, uint16 numPayments, uint256 lateFee, uint256 premiumFee) public {
        {
            bulletCalc  = new BulletRepaymentCalc();   // Repayment
            lateFeeCalc = new LateFeeCalc(lateFee);    // Flat late fee
            premiumCalc = new PremiumCalc(premiumFee); // Flat premium

            globals.setCalc(address(bulletCalc),  true);
            globals.setCalc(address(lateFeeCalc), true);
            globals.setCalc(address(premiumCalc), true);
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
            address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];
            uint256[6] memory specs = [apr, termDays, paymentInterval, loanAmt, 2000, 7];
            loan = eli.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory),  specs, calcs);
        }

        assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), loanAmt));

        {
            uint cReq = loan.collateralRequiredForDrawdown(loanAmt); // wETH required for 1_000 USDC drawdown on loan
            mint("WETH", address(eli), cReq);
            eli.approve(WETH, address(loan), cReq);
            eli.drawdown(address(loan), loanAmt);
        }
    }

    function test_bullet(uint56 _loanAmt, uint16 apr, uint16 index, uint16 numPayments) public {
        uint256 loanAmt = uint256(_loanAmt) + 10 ** 6;  // uint56(-1) = ~72b * 10 ** 6 (add 10 ** 6 so its always at least $1)

        apr = apr % 10_000;

        setUpRepayments(loanAmt, uint256(apr), index, numPayments, 100, 100);
        
        // Calculate theoretical values and sum up actual values
        uint256 totalPaid;
        uint256 sumTotal;
        uint256 sumInterest;
        {
            uint256 paymentIntervalDays = loan.paymentIntervalSeconds().div(1 days);
            uint256 totalInterest       = loanAmt * apr / 10_000 * paymentIntervalDays / 365 * loan.paymentsRemaining();
                    totalPaid           = loanAmt + totalInterest;
        }

        (uint256 lastTotal,, uint256 lastInterest,) =  loan.getNextPayment();

        mint("USDC",      address(eli),  loanAmt * 1000); // Mint enough to pay interest
        eli.approve(USDC, address(loan), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(eli));

        while (loan.paymentsRemaining() > 0) {

            (uint256 total,        uint256 principal,        uint256 interest,)       =  loan.getNextPayment();                    // USDC required for payment on loan
            (uint256 total_bullet, uint256 principal_bullet, uint256 interest_bullet) =  bulletCalc.getNextPayment(address(loan)); // USDC required for payment on loan

            assertEq(total,         total_bullet);
            assertEq(principal, principal_bullet);
            assertEq(interest,   interest_bullet);

            sumTotal  += total;
            sumInterest += interest;

            // paymentsRemaining = 1

            eli.makePayment(address(loan)); // paymentsRemaining--

            if (loan.paymentsRemaining() > 0) {
                assertEq(lastTotal,        total);
                assertEq(total,         interest);
                assertEq(principal,            0);
                assertEq(interest,  lastInterest);
            } else {
                assertEq(total,     principal + interest);
                assertEq(principal,              loanAmt);
                withinPrecision(totalPaid, sumTotal, 4);
                assertEq(beforeBal - IERC20(USDC).balanceOf(address(eli)), sumTotal); // Pays back all principal, plus interest
            }
            
            lastTotal    = total;
            lastInterest = interest;
        }
    }

    function test_late_fee(uint56 _loanAmt, uint256 apr, uint16 index, uint16 numPayments, uint256 lateFee) public {
        uint256 loanAmt = uint256(_loanAmt) + 10 ** 6;  // uint56(-1) = ~72b * 10 ** 6

        apr     = apr     % 10_000;
        lateFee = lateFee % 10_000;

        setUpRepayments(loanAmt, apr, index, numPayments, lateFee, 100);
        
        // Calculate theoretical values and sum up actual values
        uint256 totalPaid;
        uint256 sumTotal;
        {
            uint256 paymentIntervalDays = loan.paymentIntervalSeconds().div(1 days);
            uint256 totalInterest       = loanAmt * apr / 10_000 * paymentIntervalDays / 365 * loan.paymentsRemaining();
                    totalPaid           = loanAmt + totalInterest + (loanAmt + totalInterest) * lateFeeCalc.feeBips() / 10_000;
        }

        hevm.warp(loan.nextPaymentDue() + 1);  // Payment is late
        (,, uint256 lastInterest,) =  loan.getNextPayment();

        mint("USDC",      address(eli),  loanAmt * 1000); // Mint enough to pay interest
        eli.approve(USDC, address(loan), loanAmt * 1000);

        uint256 beforeBal = IERC20(USDC).balanceOf(address(eli));

        while (loan.paymentsRemaining() > 0) {
            hevm.warp(loan.nextPaymentDue() + 1);  // Payment is late

            (uint256 total,        uint256 principal,        uint256 interest,)       =  loan.getNextPayment();                    // USDC required for payment on loan
            (uint256 total_bullet, uint256 principal_bullet, uint256 interest_bullet) =  bulletCalc.getNextPayment(address(loan)); // USDC required for payment on loan
            (uint256 total_late,   uint256 principal_late,   uint256 interest_late)   =  lateFeeCalc.getLateFee(address(loan));    // USDC required for payment on loan

            eli.makePayment(address(loan));

            assertEq(total,         total_bullet +     total_late);
            assertEq(principal, principal_bullet + principal_late);
            assertEq(interest,   interest_bullet +  interest_late);

            assertEq(interest_late, total_bullet * lateFeeCalc.feeBips() / 10_000);
            assertEq(interest_late, total_late);
            assertEq(principal_late, 0);

            sumTotal += total;

            if (loan.paymentsRemaining() > 0) {
                assertEq(interest,  lastInterest);
            } else {
                assertEq(total,     principal + interest);
                assertEq(principal,              loanAmt);
                withinPrecision(totalPaid, sumTotal, 4);
                assertEq(beforeBal - IERC20(USDC).balanceOf(address(eli)), sumTotal); // Pays back all principal, plus interest
            }
            
            lastInterest = interest;
        }
    }

    function test_premium(uint56 _loanAmt, uint256 premiumFee) public {
        uint256 loanAmt = uint256(_loanAmt) + 10 ** 6;  // uint56(-1) = ~72b * 10 ** 6

        premiumFee = premiumFee % 10_000;

        setUpRepayments(loanAmt, 100, 1, 1, 100, premiumFee);
        
        // Calculate theoretical values and sum up actual values
        uint256 totalPaid = loanAmt + loanAmt * premiumCalc.premiumBips() / 10_000;

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
