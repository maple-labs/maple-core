// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Commoner.sol";
import "./user/EmergencyAdmin.sol";
import "./user/Governor.sol";
import "./user/LP.sol";
import "./user/PoolDelegate.sol";
import "./user/SecurityAdmin.sol";

import "../RepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../DebtLocker.sol";
import "../DebtLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LateFeeCalc.sol";
import "../LiquidityLockerFactory.sol";
import "../Loan.sol";
import "../LoanFactory.sol";
import "../MapleTreasury.sol";
import "../Pool.sol";
import "../PoolFactory.sol";
import "../PremiumCalc.sol";
import "../StakeLockerFactory.sol";

import "../interfaces/IERC20Details.sol";
import "../interfaces/ILoan.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

contract Treasury { }

contract LoanTest is TestUtil {

    Borrower                               ali;
    Borrower                               bob;
    Governor                               gov;
    LP                                     che;
    PoolDelegate                           sid;
    Commoner                               com;
    SecurityAdmin                          pop;
    EmergencyAdmin                         mic;

    RepaymentCalc                repaymentCalc;
    CollateralLockerFactory          clFactory;
    DebtLockerFactory                dlFactory;
    FundingLockerFactory             flFactory;
    LateFeeCalc                    lateFeeCalc;
    LiquidityLockerFactory           llFactory;
    LoanFactory                    loanFactory;
    MapleGlobals                       globals;
    MapleToken                             mpl;
    MapleTreasury                     treasury;
    Pool                                  pool; 
    PoolFactory                    poolFactory;
    PremiumCalc                    premiumCalc;
    StakeLockerFactory               slFactory;
    ChainlinkOracle                 wethOracle;
    ChainlinkOracle                 wbtcOracle;
    UsdOracle                        usdOracle;

    IBPool                               bPool;
    IStakeLocker                   stakeLocker;

    function setUp() public {

        ali = new Borrower();        // Actor: Borrower of the Loan.
        bob = new Borrower();        // Actor: Borrower of the Loan.
        gov = new Governor();        // Actor: Governor of Maple.
        com = new Commoner();        // Actor: Any user or an incentive seeker.
        che = new LP();              // Actor: Liquidity provider.
        sid = new PoolDelegate();    // Actor: Manager of the Pool.
        pop = new SecurityAdmin();   // Actor: Security Admin of the Loan.
        mic = new EmergencyAdmin();  // Actor: Emergency Admin of the protocol.

        mpl      = new MapleToken("MapleToken", "MAPL", USDC);
        globals  = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        treasury = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals));

        flFactory     = new FundingLockerFactory();         // Setup the FL factory to facilitate Loan factory functionality.
        clFactory     = new CollateralLockerFactory();      // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory   = new LoanFactory(address(globals));  // Create Loan factory.
        slFactory     = new StakeLockerFactory();           // Setup the SL factory to facilitate Pool factory functionality.
        llFactory     = new LiquidityLockerFactory();       // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory   = new PoolFactory(address(globals));  // Create pool factory.
        dlFactory     = new DebtLockerFactory();            // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        repaymentCalc = new RepaymentCalc();                // Repayment model.
        lateFeeCalc   = new LateFeeCalc(0);                 // Flat 0% fee
        premiumCalc   = new PremiumCalc(500);               // Flat 5% premium

        /*** Globals administrative actions ***/
        gov.setPoolDelegateAllowlist(address(sid), true);
        gov.setMapleTreasury(address(treasury));
        gov.setAdmin(address(mic));

        /*** Validate all relevant contracts in Globals ***/
        gov.setValidLoanFactory(address(loanFactory), true);
        gov.setValidPoolFactory(address(poolFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);

        gov.setCalc(address(repaymentCalc), true);
        gov.setCalc(address(lateFeeCalc),   true);
        gov.setCalc(address(premiumCalc),   true);
        gov.setCollateralAsset(WETH,        true);
        gov.setLoanAsset(USDC,              true);

        /*** Set up oracles ***/
        wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        usdOracle  = new UsdOracle();
        
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));

        /*** Mint balances to relevant actors ***/
        mint("WETH", address(ali),          10 ether);
        mint("USDC", address(che),        5000 * USD);
        mint("USDC", address(ali),         500 * USD);
        mint("USDC", address(this), 50_000_000 * USD);

        /*** Create and finalize MPL-USDC 50-50 Balancer Pool ***/
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool()); // Initialize MPL/USDC Balancer pool (without finalizing)

        IERC20(USDC).approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool), MAX_UINT);

        bPool.bind(USDC,         1_650_000 * USD, 5 ether);  // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl),   550_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight
        bPool.finalize();
        bPool.transfer(address(sid), 100 * WAD);  // Give PD a balance of BPTs to finalize pool

        gov.setValidBalancerPool(address(bPool), true);

        /*** Create Liqiuidty Pool ***/
        pool = Pool(sid.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT  // liquidityCap value
        ));

        /*** Pool Delegate stakes and finalizes Pool ***/ 
        stakeLocker = IStakeLocker(pool.stakeLocker());
        sid.approve(address(bPool), address(stakeLocker), 50 * WAD);
        sid.stake(address(stakeLocker), 50 * WAD);
        sid.finalize(address(pool));  // PD that staked can finalize
        sid.setOpenToPublic(address(pool), true);
        assertEq(uint256(pool.poolState()), 1);  // Finalize

        /*** LP deposits USDC into Pool ***/
        che.approve(USDC, address(pool), MAX_UINT);
        che.deposit(address(pool), 5000 * USD);  
    }

    function test_createLoan() public {
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        // Can't create a loan with DAI since stakingAsset uses USDC.
        assertTrue(!ali.try_createLoan(address(loanFactory), DAI, WETH, address(flFactory), address(clFactory), specs, calcs));

        Loan loan = ali.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
    
        assertEq(address(loan.loanAsset()),        USDC);
        assertEq(address(loan.collateralAsset()),  WETH);
        assertEq(loan.flFactory(),                 address(flFactory));
        assertEq(loan.clFactory(),                 address(clFactory));
        assertEq(loan.borrower(),                  address(ali));
        assertEq(loan.createdAt(),                 block.timestamp);
        assertEq(loan.apr(),                       specs[0]);
        assertEq(loan.termDays(),                  specs[1]);
        assertEq(loan.paymentsRemaining(),         specs[1] / specs[2]);
        assertEq(loan.paymentIntervalSeconds(),    specs[2] * 1 days);
        assertEq(loan.requestAmount(),             specs[3]);
        assertEq(loan.collateralRatio(),           specs[4]);
        assertEq(loan.fundingPeriodSeconds(),      specs[5] * 1 days);
        assertEq(loan.repaymentCalc(),             address(repaymentCalc));
        assertEq(loan.lateFeeCalc(),               address(lateFeeCalc));
        assertEq(loan.premiumCalc(),               address(premiumCalc));
    }

    function test_fundLoan() public {
        uint256[6] memory specs = [500, 90, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan loan = ali.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        address fundingLocker   = loan.fundingLocker();
        address liquidityLocker = pool.liquidityLocker();
    
        // Note: Cannot do pre-state check for LoanFDT balance of debtLocker since it is not instantiated
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),            0);
        assertEq(IERC20(USDC).balanceOf(address(liquidityLocker)), 5000 * USD);

        // Loan-specific pause by Borrower
        assertTrue(!loan.paused());
        assertTrue(!com.try_pause(address(loan)));
        assertTrue( ali.try_pause(address(loan)));
        assertTrue(loan.paused());
        assertTrue(!sid.try_fundLoan(address(pool), address(loan), address(dlFactory), 2500 * USD));

        assertTrue(!com.try_unpause(address(loan)));
        assertTrue( ali.try_unpause(address(loan)));
        assertTrue(!loan.paused());
        assertTrue(sid.try_fundLoan(address(pool), address(loan), address(dlFactory), 2500 * USD));

        address debtLocker = pool.debtLockers(address(loan), address(dlFactory));

        assertEq(IERC20(loan).balanceOf(address(debtLocker)),      2500 * WAD);
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),   2500 * USD);
        assertEq(IERC20(USDC).balanceOf(address(liquidityLocker)), 2500 * USD);

        // Protocol-wide pause by Emergency Admin
        assertTrue(!com.try_setProtocolPause(address(globals), true));
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(globals.protocolPaused());
        assertTrue(!sid.try_fundLoan(address(pool), address(loan), address(dlFactory), 2500 * USD));

        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(!globals.protocolPaused());
        assertTrue(sid.try_fundLoan(address(pool), address(loan), address(dlFactory), 2500 * USD));

        assertEq(IERC20(loan).balanceOf(address(debtLocker)),      5000 ether);
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),   5000 * USD);
        assertEq(IERC20(USDC).balanceOf(address(liquidityLocker)),          0);
    }

    function createAndFundLoan(address _interestStructure) internal returns (Loan loan) {
        uint256[6] memory specs = [500, 90, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [_interestStructure, address(lateFeeCalc), address(premiumCalc)];

        loan = ali.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
    
        sid.fundLoan(address(pool), address(loan), address(dlFactory), 5000 * USD); 
    }

    function test_collateralRequiredForDrawdown() public {
        Loan loan = createAndFundLoan(address(repaymentCalc));

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(1000 * USD);
        withinDiff(reqCollateral * globals.getLatestPrice(address(WETH)) * USD / WAD / 10 ** 8, 200 * USD, 1);  // 20% of $1000, 1 wei diff
    }

    function test_drawdown_protocol_paused() external {
        Loan loan = createAndFundLoan(address(repaymentCalc));

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(5000 * USD);
        ali.approve(WETH, address(loan), reqCollateral);

        // Pause protocol and attempt drawdown()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!ali.try_drawdown(address(loan), 5000 * USD));

        // Unpause protocol and drawdown()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(ali.try_drawdown(address(loan), 5000 * USD));
    }

    function test_drawdown() public {
        Loan loan = createAndFundLoan(address(repaymentCalc));

        assertTrue(!bob.try_drawdown(address(loan), 1000 * USD));  // Non-borrower can't drawdown
        assertTrue(!ali.try_drawdown(address(loan), 1000 * USD));  // Can't drawdown without approving collateral

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(1000 * USD);
        ali.approve(WETH, address(loan), reqCollateral);

        assertTrue(!ali.try_drawdown(address(loan), 1000 * USD - 1));  // Can't drawdown less than requestAmount
        assertTrue(!ali.try_drawdown(address(loan), 5000 * USD + 1));  // Can't drawdown more than fundingLocker balance

        address fundingLocker = loan.fundingLocker();
        uint pre = IERC20(USDC).balanceOf(address(ali));

        assertEq(IERC20(WETH).balanceOf(address(ali)),    10 ether);  // Borrower collateral balance
        assertEq(IERC20(USDC).balanceOf(fundingLocker), 5000 * USD);  // Funding locker reqAssset balance
        assertEq(IERC20(USDC).balanceOf(address(loan)),          0);  // Loan vault loanAsset balance
        assertEq(loan.principalOwed(),                           0);  // Principal owed
        assertEq(uint256(loan.loanState()),                      0);  // Loan state: Live

        // Fee related variables pre-check.
        assertEq(loan.feePaid(),                            0);  // feePaid amount
        assertEq(loan.excessReturned(),                     0);  // excessReturned amount
        assertEq(IERC20(USDC).balanceOf(address(treasury)), 0);  // Treasury loanAsset balance

        assertTrue(ali.try_drawdown(address(loan), 1000 * USD));     // Borrow draws down 1000 USDC

        assertEq(IERC20(WETH).balanceOf(address(ali)),                     10 ether - reqCollateral);  // Borrower collateral balance
        assertEq(IERC20(WETH).balanceOf(address(loan.collateralLocker())),            reqCollateral);  // Collateral locker collateral balance

        assertEq(IERC20(USDC).balanceOf(fundingLocker),                   0);  // Funding locker reqAssset balance
        assertEq(IERC20(USDC).balanceOf(address(loan)),          4005 * USD);  // Loan vault loanAsset balance
        assertEq(IERC20(USDC).balanceOf(address(ali)),      990 * USD + pre);  // Lender loanAsset balance
        assertEq(loan.principalOwed(),                           1000 * USD);  // Principal owed
        assertEq(uint256(loan.loanState()),                               1);  // Loan state: Active

        assertEq(loan.nextPaymentDue(), block.timestamp + loan.paymentIntervalSeconds());  // Next payment due timestamp calculated from time of drawdown

        // Fee related variables post-check.
        assertEq(loan.feePaid(),                               5 * USD);  // Drawdown amount
        assertEq(loan.excessReturned(),                     4000 * USD);  // Principal owed
        assertEq(IERC20(USDC).balanceOf(address(treasury)),    5 * USD);  // Treasury loanAsset balance

        // Test FDT accounting
        address debtLocker = pool.debtLockers(address(loan), address(dlFactory));
        withinDiff(loan.withdrawableFundsOf(address(debtLocker)), 4005 * USD, 1);

        // Can't drawdown() loan after it has already been called.
        assertTrue(!ali.try_drawdown(address(loan), 1000 * USD));
    }

    function test_makePayment() public {

        Loan loan = createAndFundLoan(address(repaymentCalc));

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Live

        assertTrue(!ali.try_makePayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collateral and drawdown loan.
        ali.approve(WETH, address(loan), 0.4 ether);
        assertTrue(ali.try_drawdown(address(loan), 1000 * USD));  // Borrow draws down 1000 USDC

        address collateralLocker = loan.collateralLocker();

        // Warp to *300 seconds* before next payment is due
        assertEq(loan.nextPaymentDue(), block.timestamp + loan.paymentIntervalSeconds());
        hevm.warp(loan.nextPaymentDue() - 300);
        assertEq(block.timestamp, loan.nextPaymentDue() - 300);

        assertTrue(!ali.try_makePayment(address(loan)));  // Can't makePayment with lack of approval

        // Approve 1st of 3 payments.
        (uint _amt, uint _pri, uint _int, uint _due,) = loan.getNextPayment();
        ali.approve(USDC, address(loan), _amt);

        // Before state
        assertEq(uint256(loan.loanState()),          1);  // Loan state is Active, accepting payments
        assertEq(loan.principalOwed(),      1000 * USD);  // Initial drawdown amount.
        assertEq(loan.principalPaid(),               0);
        assertEq(loan.interestPaid(),                0);
        assertEq(loan.paymentsRemaining(),           3);
        assertEq(loan.nextPaymentDue(),           _due);

        // Pause protocol and attempt makePayment()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!ali.try_makePayment(address(loan)));

        // Unpause protocol and makePayment()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(ali.try_makePayment(address(loan)));  // Make payment.

        uint _nextPaymentDue = _due + loan.paymentIntervalSeconds();

        // After state
        assertEq(uint256(loan.loanState()),               1);  // Loan state is Active (unless final payment, then 2)
        assertEq(loan.principalOwed(),           1000 * USD);  // Initial drawdown amount.
        assertEq(loan.principalPaid(),                 _pri);
        assertEq(loan.interestPaid(),                  _int);
        assertEq(loan.paymentsRemaining(),                2);
        assertEq(loan.nextPaymentDue(),     _nextPaymentDue);

        // Approve 2nd of 3 payments.
        (_amt, _pri, _int, _due,) = loan.getNextPayment();
        ali.approve(USDC, address(loan), _amt);
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loan)));

        _nextPaymentDue = _due + loan.paymentIntervalSeconds();
        
        // After state
        assertEq(uint256(loan.loanState()),               1);  // Loan state is Active (unless final payment, then 2)
        assertEq(loan.principalOwed(),           1000 * USD);  // Initial drawdown amount.
        assertEq(loan.principalPaid(),                 _pri);
        assertEq(loan.interestPaid(),              _int * 2);
        assertEq(loan.paymentsRemaining(),                1);
        assertEq(loan.nextPaymentDue(),     _nextPaymentDue);

        // Approve 3nd of 3 payments.
        (_amt, _pri, _int, _due,) = loan.getNextPayment();
        ali.approve(USDC, address(loan), _amt);
        
        // Check collateral locker balance.
        uint256 reqCollateral   = loan.collateralRequiredForDrawdown(1000 * USD);
        IERC20Details collateralAsset = IERC20Details(address(loan.collateralAsset()));
        uint _delta = collateralAsset.balanceOf(address(ali));
        assertEq(collateralAsset.balanceOf(collateralLocker), reqCollateral);
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loan)));

        _nextPaymentDue = _due + loan.paymentIntervalSeconds();
        
        // After state, state variables.
        assertEq(uint256(loan.loanState()),               2);  // Loan state is Matured (final payment)
        assertEq(loan.principalOwed(),                    0);  // Final payment, all principal paid for InterestOnly loan
        assertEq(loan.principalPaid(),                 _pri);
        assertEq(loan.interestPaid(),              _int * 3);
        assertEq(loan.paymentsRemaining(),                0);
        assertEq(loan.nextPaymentDue(),                   0);

        // Collateral locker after state.
        assertEq(collateralAsset.balanceOf(collateralLocker),                      0);
        assertEq(collateralAsset.balanceOf(address(ali)),     _delta + reqCollateral);

    }
    
    function test_makePayment_late() public {
        Loan loan = createAndFundLoan(address(repaymentCalc));

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Live

        assertTrue(!ali.try_makePayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collatearl and drawdown loan.
        ali.approve(WETH, address(loan), 0.4 ether);
        assertTrue(ali.try_drawdown(address(loan), 1000 * USD));  // Borrow draws down 1000 USDC

        address collateralLocker = loan.collateralLocker();

        // Warp to *300 seconds* before next payment is due
        assertEq(loan.nextPaymentDue(), block.timestamp + loan.paymentIntervalSeconds());
        hevm.warp(loan.nextPaymentDue() - 300);
        assertEq(block.timestamp, loan.nextPaymentDue() - 300);

        assertTrue(!ali.try_makePayment(address(loan)));  // Can't makePayment with lack of approval

        // Approve 1st of 3 payments.
        (uint _amt, uint _pri, uint _int, uint _due,) = loan.getNextPayment();
        ali.approve(USDC, address(loan), _amt);

        // Before state
        assertEq(uint256(loan.loanState()),          1);  // Loan state is Active, accepting payments
        assertEq(loan.principalOwed(),      1000 * USD);  // Initial drawdown amount.
        assertEq(loan.principalPaid(),               0);
        assertEq(loan.interestPaid(),                0);
        assertEq(loan.paymentsRemaining(),           3);
        assertEq(loan.nextPaymentDue(),           _due);

        // Warp to *300 seconds* after next payment is due
        hevm.warp(loan.nextPaymentDue() + globals.gracePeriod());
        assertEq(block.timestamp, loan.nextPaymentDue() + globals.gracePeriod());

        // Make payment.
        assertTrue(ali.try_makePayment(address(loan)));

        uint _nextPaymentDue = _due + loan.paymentIntervalSeconds();

        // After state
        assertEq(uint256(loan.loanState()),               1);  // Loan state is Active (unless final payment, then 2)
        assertEq(loan.principalOwed(),           1000 * USD);  // Initial drawdown amount.
        assertEq(loan.principalPaid(),                 _pri);
        assertEq(loan.interestPaid(),                  _int);
        assertEq(loan.paymentsRemaining(),                2);
        assertEq(loan.nextPaymentDue(),     _nextPaymentDue);

        // Approve 2nd of 3 payments.
        (_amt, _pri, _int, _due,) = loan.getNextPayment();
        ali.approve(USDC, address(loan), _amt);

        // Warp to *300 seconds* after next payment is due
        hevm.warp(loan.nextPaymentDue() + globals.gracePeriod());
        assertEq(block.timestamp, loan.nextPaymentDue() + globals.gracePeriod());
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loan)));

        _nextPaymentDue = _due + loan.paymentIntervalSeconds();
        
        // After state
        assertEq(uint256(loan.loanState()),               1);  // Loan state is Active (unless final payment, then 2)
        assertEq(loan.principalOwed(),           1000 * USD);  // Initial drawdown amount.
        assertEq(loan.principalPaid(),                 _pri);
        assertEq(loan.interestPaid(),              _int * 2);
        assertEq(loan.paymentsRemaining(),                1);
        assertEq(loan.nextPaymentDue(),     _nextPaymentDue);

        // Approve 3nd of 3 payments.
        (_amt, _pri, _int, _due,) = loan.getNextPayment();
        ali.approve(USDC, address(loan), _amt);
        
        // Check collateral locker balance.
        uint256 reqCollateral   = loan.collateralRequiredForDrawdown(1000 * USD);
        IERC20Details collateralAsset = IERC20Details(address(loan.collateralAsset()));
        uint _delta = collateralAsset.balanceOf(address(ali));
        assertEq(collateralAsset.balanceOf(collateralLocker), reqCollateral);

        // Warp to *300 seconds* after next payment is due
        hevm.warp(loan.nextPaymentDue() + globals.gracePeriod());
        assertEq(block.timestamp, loan.nextPaymentDue() + globals.gracePeriod());
        
        // Make payment.
        assertTrue(ali.try_makePayment(address(loan)));

        _nextPaymentDue = _due + loan.paymentIntervalSeconds();
        
        // After state, state variables.
        assertEq(uint256(loan.loanState()),               2);  // Loan state is Matured (final payment)
        assertEq(loan.principalOwed(),                    0);  // Final payment, all principal paid for InterestOnly loan
        assertEq(loan.principalPaid(),                 _pri);
        assertEq(loan.interestPaid(),              _int * 3);
        assertEq(loan.paymentsRemaining(),                0);
        assertEq(loan.nextPaymentDue(),                   0);

        // Collateral locker after state.
        assertEq(collateralAsset.balanceOf(collateralLocker),  0);
        assertEq(collateralAsset.balanceOf(address(ali)),     _delta + reqCollateral);
    }

    function test_unwind_loan() public {

        Loan loan = createAndFundLoan(address(repaymentCalc));

        // Warp to the drawdownGracePeriod ... can't call unwind() yet
        hevm.warp(loan.createdAt() + globals.drawdownGracePeriod());
        assertTrue(!ali.try_unwind(address(loan)));

        uint256 flBalance_pre   = IERC20(loan.loanAsset()).balanceOf(loan.fundingLocker());
        uint256 loanBalance_pre = IERC20(loan.loanAsset()).balanceOf(address(loan));
        uint256 loanState_pre   = uint256(loan.loanState());

        // Warp 1 more second ... can call unwind()
        hevm.warp(loan.createdAt() + globals.drawdownGracePeriod() + 1);

        // Pause protocol and attempt unwind()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!ali.try_unwind(address(loan)));

        // Unpause protocol and unwind()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(ali.try_unwind(address(loan)));

        uint256 flBalance_post   = IERC20(loan.loanAsset()).balanceOf(loan.fundingLocker());
        uint256 loanBalance_post = IERC20(loan.loanAsset()).balanceOf(address(loan));
        uint256 loanState_post   = uint256(loan.loanState());

        assertEq(loanBalance_pre, 0);
        assertEq(loanState_pre,   0);

        assertEq(flBalance_post, 0);
        assertEq(loanState_post, 3);

        assertEq(flBalance_pre, 5000 * USD);
        assertEq(loanBalance_post, 5000 * USD);

        assertEq(loan.excessReturned(), loanBalance_post);

        assertEq(IERC20(USDC).balanceOf(address(bob)), 0);

        // Pause protocol and attempt withdrawFunds() (through claim)
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_claim(address(pool), address(loan), address(dlFactory)));

        // Unpause protocol and withdrawFunds() (through claim)
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_claim(address(pool), address(loan), address(dlFactory)));

        withinDiff(IERC20(USDC).balanceOf(address(pool.liquidityLocker())), 5000 * USD, 1);
        withinDiff(IERC20(loan.loanAsset()).balanceOf(address(loan)),                0, 1);

        // Can't unwind() loan after it has already been called.
        assertTrue(!ali.try_unwind(address(loan)));
    }


    function test_trigger_default() public {
        ILoan loan = ILoan(address(createAndFundLoan(address(repaymentCalc))));

        address debtLocker = pool.debtLockers(address(loan), address(dlFactory));

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(5000 * USD);
        ali.approve(WETH, address(loan), reqCollateral);

        assertEq(loan.loanState(), 0);  // `Live` state

        assertTrue(ali.try_drawdown(address(loan), 5000 * USD));  // Draw down the loan.

        assertEq(loan.loanState(), 1);  // `Active` state

        assertTrue(!sid.try_triggerDefault(address(pool), address(loan), address(dlFactory)));  // Should fail to trigger default because current time is still less than the `nextPaymentDue`.
        assertTrue(!com.try_triggerDefault(address(loan)));                                     // Failed because commoner in not allowed to default the loan because they do not own any LoanFDTs.

        hevm.warp(loan.nextPaymentDue() + 1);

        assertTrue(!sid.try_triggerDefault(address(pool), address(loan), address(dlFactory)));  // Failed because still loan has gracePeriod to repay the dues.
        assertTrue(!com.try_triggerDefault(address(loan)));                                     // Failed because still commoner is not allowed to default the loan.

        hevm.warp(loan.nextPaymentDue() + globals.gracePeriod());

        assertTrue(!sid.try_triggerDefault(address(pool), address(loan), address(dlFactory)));  // Failed because still loan has gracePeriod to repay the dues.
        assertTrue(!com.try_triggerDefault(address(loan)));                                     // Failed because still commoner is not allowed to default the loan.

        hevm.warp(loan.nextPaymentDue() + globals.gracePeriod() + 1);

        assertTrue(!com.try_triggerDefault(address(loan)));  // Failed because still commoner is not allowed to default the loan.

        // Sid's Pool currently has 100% of LoanFDTs, so he can trigger the loan default.
        // For this test, minLoanEquity is transferred to the commoner to test the minimum loan equity condition.
        assertEq(loan.totalSupply(),      5000 * WAD); 
        assertEq(globals.minLoanEquity(),       2000);  // 20%

        // Simulate transfer of LoanFDTs from DebtLocker to commoner (<20% of total supply)
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(com), 0)), // Mint tokens
            bytes32(uint256(1000 * WAD - 1))
        );
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(debtLocker), 0)), // Overwrite balance
            bytes32(uint256(4000 * WAD + 1))
        );

        assertTrue(!com.try_triggerDefault(address(loan)));  // Failed because still commoner is not allowed to default the loan.

        // "Transfer" 1 more wei to meet 20% minimum equity requirement
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(com), 0)), // Mint tokens
            bytes32(uint256(1000 * WAD))
        );
        hevm.store(
            address(loan),
            keccak256(abi.encode(address(debtLocker), 0)), // Overwrite balance
            bytes32(uint256(4000 * WAD))
        );

        assertTrue(com.try_triggerDefault(address(loan)));  // Now with 20% of loan equity, a loan can be defaulted
        assertEq(loan.loanState(), 4);
    }

    function test_calc_min_amount() external {
        Loan loan = createAndFundLoan(address(repaymentCalc));

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(5000 * USD);
        ali.approve(WETH, address(loan), reqCollateral);

        assertTrue(ali.try_drawdown(address(loan), 5000 * USD));  // Draw down the loan.

        uint256 expectedAmount = (reqCollateral * globals.getLatestPrice(address(loan.collateralAsset()))) / globals.getLatestPrice(address(loan.loanAsset()));

        assertEq((expectedAmount * USD) / WAD, loan.getExpectedAmountRecovered());
    }

    function test_makeFullPayment() public {

        Loan loan = createAndFundLoan(address(repaymentCalc));

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Live

        assertTrue(!ali.try_makeFullPayment(address(loan)));  // Can't makePayment when State != Active

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(1000 * USD);
        // Approve collateral and drawdown loan.
        ali.approve(WETH, address(loan), reqCollateral);
        assertTrue(ali.try_drawdown(address(loan), 1000 * USD));  // Borrow draws down 1000 USDC

        address collateralLocker = loan.collateralLocker();

        // Warp to *300 seconds* before next payment is due
        assertEq(loan.nextPaymentDue(), block.timestamp + loan.paymentIntervalSeconds());
        hevm.warp(loan.nextPaymentDue() - 300);
        assertEq(block.timestamp, loan.nextPaymentDue() - 300);

        assertTrue(!ali.try_makeFullPayment(address(loan)));  // Can't makePayment with lack of approval

        // Approve full payment.
        (uint _amt, uint _pri, uint _int) = loan.getFullPayment();
        ali.approve(USDC, address(loan), _amt);
        assertEq(IERC20(USDC).allowance(address(ali), address(loan)), _amt);

        // Before state
        assertEq(uint256(loan.loanState()),          1);  // Loan state is Active, accepting payments
        assertEq(loan.principalOwed(),      1000 * USD);  // Initial drawdown amount.
        assertEq(loan.principalPaid(),               0);
        assertEq(loan.interestPaid(),                0);
        assertEq(loan.paymentsRemaining(),           3);

        IERC20Details collateralAsset = IERC20Details(address(loan.collateralAsset()));
        uint256 _delta                = collateralAsset.balanceOf(address(ali));
        uint256 _usdcDelta            = IERC20(USDC).balanceOf(address(loan));

        // Pause protocol and attempt makeFullPayment()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!ali.try_makeFullPayment(address(loan)));

        // Unpause protocol and makeFullPayment()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(ali.try_makeFullPayment(address(loan)));  // Make full payment.

        // After state
        assertEq(IERC20(USDC).balanceOf(address(loan)),  _usdcDelta + _amt);
        assertEq(uint256(loan.loanState()),                              2);  // Loan state is Matured
        assertEq(loan.principalOwed(),                                   0);  // Initial drawdown amount.
        assertEq(loan.principalPaid(),                                _pri);
        assertEq(loan.interestPaid(),                                 _int);
        assertEq(loan.paymentsRemaining(),                               0);

        // Collateral locker after state.
        assertEq(collateralAsset.balanceOf(collateralLocker),                      0);
        assertEq(collateralAsset.balanceOf(address(ali)),     _delta + reqCollateral);
    }

    function test_reclaim_erc20() external {
        Loan loan = createAndFundLoan(address(repaymentCalc));

        // Fund the loan with different kind of asset.
        mint("USDC", address(loan), 1000 * USD);
        mint("DAI",  address(loan), 1000 * WAD);
        mint("WETH", address(loan),  100 * WAD);

        Governor fakeGov = new Governor();

        uint256 beforeBalanceDAI   = IERC20(DAI).balanceOf(address(gov));
        uint256 beforeBalanceWETH  = IERC20(WETH).balanceOf(address(gov));

        assertTrue(!fakeGov.try_reclaimERC20(address(loan), DAI));
        assertTrue(    !gov.try_reclaimERC20(address(loan), USDC));
        assertTrue(    !gov.try_reclaimERC20(address(loan), address(0)));
        assertTrue(     gov.try_reclaimERC20(address(loan), WETH));
        assertTrue(     gov.try_reclaimERC20(address(loan), DAI));

        uint256 afterBalanceDAI   = IERC20(DAI).balanceOf(address(gov));
        uint256 afterBalanceWETH  = IERC20(WETH).balanceOf(address(gov));

        assertEq(afterBalanceDAI - beforeBalanceDAI,    1000 * WAD);
        assertEq(afterBalanceWETH - beforeBalanceWETH,   100 * WAD);
    }

    function test_setAdmin() public {
        Loan loan = createAndFundLoan(address(repaymentCalc));

        // Pause protocol and attempt setAdmin()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!ali.try_setAdmin(address(loan), address(pop), true));
        assertTrue(!loan.admins(address(pop)));

        // Unpause protocol and setAdmin()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(ali.try_setAdmin(address(loan), address(pop), true));
        assertTrue(loan.admins(address(pop)));
    }
}
