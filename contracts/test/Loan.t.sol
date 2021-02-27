// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/Lender.sol";

import "../RepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LateFeeCalc.sol";
import "../LoanFactory.sol";
import "../PremiumCalc.sol";

import "../interfaces/IERC20Details.sol";
import "../interfaces/ILoan.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

contract Treasury { }

contract Commoner {
    function try_trigger_default(address loan) external returns (bool ok) {
        string memory sig = "triggerDefault()";
        (ok,) = loan.call(abi.encodeWithSignature(sig));
    }
}

contract LoanTest is TestUtil {

    Borrower                         ali;
    Governor                         gov;
    Lender                           bob;
    Commoner                         com;

    RepaymentCalc          repaymentCalc;
    CollateralLockerFactory    clFactory;
    FundingLockerFactory       flFactory;
    LateFeeCalc              lateFeeCalc;
    LoanFactory              loanFactory;
    MapleToken                       mpl;
    MapleGlobals                 globals;
    PremiumCalc              premiumCalc;
    Treasury                         trs;
    ChainlinkOracle           wethOracle;
    ChainlinkOracle           wbtcOracle;
    UsdOracle                  usdOracle;

    ERC20                     fundsToken;

    function setUp() public {

        ali         = new Borrower();       // Actor: Borrower of the Loan.
        gov         = new Governor();       // Actor: Governor of Maple.
        bob         = new Lender();         // Actor: Individual lender.
        com         = new Commoner();       // Actor: Any user or an incentive seeker.

        mpl           = new MapleToken("MapleToken", "MAPL", USDC);
        globals       = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        flFactory     = new FundingLockerFactory();
        clFactory     = new CollateralLockerFactory();
        repaymentCalc = new RepaymentCalc();
        lateFeeCalc   = new LateFeeCalc(0);   // Flat 0% fee
        premiumCalc   = new PremiumCalc(500); // Flat 5% premium
        loanFactory   = new LoanFactory(address(globals));
        trs           = new Treasury();

        gov.setCalc(address(repaymentCalc),         true);
        gov.setCalc(address(lateFeeCalc),        true);
        gov.setCalc(address(premiumCalc),        true);
        gov.setCollateralAsset(WETH,             true);
        gov.setLoanAsset(USDC,                   true);

        wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        usdOracle  = new UsdOracle();
        
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setMapleTreasury(address(trs));

        mint("WETH", address(ali),   10 ether);
        mint("USDC", address(bob), 5000 * USD);
        mint("USDC", address(ali),  500 * USD);
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
        assertEq(loan.nextPaymentDue(),            block.timestamp + loan.paymentIntervalSeconds());
    }

    function test_fundLoan() public {
        uint256[6] memory specs = [500, 90, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan loan = ali.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        address fundingLocker = loan.fundingLocker();

        bob.approve(USDC, address(loan), 5000 * USD);
    
        assertEq(IERC20(loan).balanceOf(address(ali)),                    0);
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),          0);
        assertEq(IERC20(USDC).balanceOf(address(bob)),           5000 * USD);

        bob.fundLoan(address(loan), 5000 * USD, address(ali));

        assertEq(IERC20(loan).balanceOf(address(ali)),           5000 ether);
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 5000 * USD);
        assertEq(IERC20(USDC).balanceOf(address(bob)),                    0);
    }

    function createAndFundLoan(address _interestStructure) internal returns (Loan loan) {
        uint256[6] memory specs = [500, 90, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [_interestStructure, address(lateFeeCalc), address(premiumCalc)];

        loan = ali.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        bob.approve(USDC, address(loan), 5000 * USD);
    
        bob.fundLoan(address(loan), 5000 * USD, address(bob));
    }

    function test_collateralRequiredForDrawdown() public {
        Loan loan = createAndFundLoan(address(repaymentCalc));

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(1000 * USD);
        withinDiff(reqCollateral * globals.getLatestPrice(address(WETH)) * USD / WAD / 10 ** 8, 200 * USD, 1);  // 20% of $1000, 1 wei diff
    }

    function test_drawdown() public {
        Loan loan = createAndFundLoan(address(repaymentCalc));

        assertTrue(!bob.try_drawdown(address(loan), 1000 * USD));  // Non-borrower can't drawdown
        assertTrue(!ali.try_drawdown(address(loan), 1000 * USD));  // Can't drawdown without approving collateral

        ali.approve(WETH, address(loan), 0.4 ether);

        assertTrue(!ali.try_drawdown(address(loan), 1000 * USD - 1));  // Can't drawdown less than requestAmount
        assertTrue(!ali.try_drawdown(address(loan), 5000 * USD + 1));  // Can't drawdown more than fundingLocker balance

        address fundingLocker = loan.fundingLocker();
        uint pre = IERC20(USDC).balanceOf(address(ali));

        assertEq(IERC20(WETH).balanceOf(address(ali)),    10 ether);  // Borrower collateral balance
        assertEq(IERC20(loan).balanceOf(address(bob)),  5000 ether);  // Lender loan token balance
        assertEq(IERC20(USDC).balanceOf(fundingLocker), 5000 * USD);  // Funding locker reqAssset balance
        assertEq(IERC20(USDC).balanceOf(address(loan)),          0);  // Loan vault reqAsset balance
        assertEq(loan.drawdownAmount(),                          0);  // Drawdown amount
        assertEq(loan.principalOwed(),                           0);  // Principal owed
        assertEq(uint256(loan.loanState()),                      0);  // Loan state: Live

        // Fee related variables pre-check.
        assertEq(loan.feePaid(),                       0);  // feePaid amount
        assertEq(loan.excessReturned(),                0);  // excessReturned amount
        assertEq(IERC20(USDC).balanceOf(address(trs)), 0);  // Treasury reqAsset balance

        assertTrue(ali.try_drawdown(address(loan), 1000 * USD));     // Borrow draws down 1000 USDC

        // TODO: Come up with better test for live price feeds.
        // assertEq(IERC20(WETH).balanceOf(address(ali)),            9.6 ether);  // Borrower collateral balance
        // assertEq(IERC20(WETH).balanceOf(collateralLocker),        0.4 ether);  // Collateral locker collateral balance

        assertEq(IERC20(loan).balanceOf(address(bob)),           5000 ether);  // Lender loan token balance
        assertEq(IERC20(USDC).balanceOf(fundingLocker),                   0);  // Funding locker reqAssset balance
        assertEq(IERC20(USDC).balanceOf(address(loan)),          4005 * USD);  // Loan vault reqAsset balance
        assertEq(IERC20(USDC).balanceOf(address(ali)),      990 * USD + pre);  // Lender reqAsset balance
        assertEq(loan.drawdownAmount(),                          1000 * USD);  // Drawdown amount
        assertEq(loan.principalOwed(),                           1000 * USD);  // Principal owed
        assertEq(uint256(loan.loanState()),                               1);  // Loan state: Active

        
        // Fee related variables post-check.
        assertEq(loan.feePaid(),                          5 * USD);  // Drawdown amount
        assertEq(loan.excessReturned(),                4000 * USD);  // Principal owed
        assertEq(IERC20(USDC).balanceOf(address(trs)),    5 * USD);  // Treasury reqAsset balance

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
        (uint _amt, uint _pri, uint _int, uint _due) = loan.getNextPayment();
        ali.approve(USDC, address(loan), _amt);

        // Before state
        assertEq(uint256(loan.loanState()),          1);  // Loan state is Active, accepting payments
        assertEq(loan.principalOwed(),      1000 * USD);  // Initial drawdown amount.
        assertEq(loan.principalPaid(),               0);
        assertEq(loan.interestPaid(),                0);
        assertEq(loan.paymentsRemaining(),           3);
        assertEq(loan.nextPaymentDue(),           _due);

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
        (_amt, _pri, _int, _due) = loan.getNextPayment();
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
        (_amt, _pri, _int, _due) = loan.getNextPayment();
        ali.approve(USDC, address(loan), _amt);
        
        // Check collateral locker balance.
        uint256 reqCollateral   = loan.collateralRequiredForDrawdown(1000 * USD);
        IERC20Details collateralAsset = loan.collateralAsset();
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
        (uint _amt, uint _pri, uint _int, uint _due) = loan.getNextPayment();
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
        (_amt, _pri, _int, _due) = loan.getNextPayment();
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
        (_amt, _pri, _int, _due) = loan.getNextPayment();
        ali.approve(USDC, address(loan), _amt);
        
        // Check collateral locker balance.
        uint256 reqCollateral   = loan.collateralRequiredForDrawdown(1000 * USD);
        IERC20Details collateralAsset = loan.collateralAsset();
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

        // Can't unwind() loan after it has already been called.
        assertTrue(!ali.try_unwind(address(loan)));
    }

    function test_trigger_default() public {
        ILoan loan = ILoan(address(createAndFundLoan(address(repaymentCalc))));

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(5000 * USD);
        ali.approve(WETH, address(loan), reqCollateral);

        assertTrue(ali.try_drawdown(address(loan), 5000 * USD));  // Draw down the loan.

        assertTrue(!bob.try_trigger_default(address(loan)), "Should fail to trigger default by lender");   // Should fail to trigger default because current time is still less than the `nextPaymentDue`.
        assertEq(loan.loanState(), 1,                       "Loan State should remain `Active`");
        assertTrue(!com.try_trigger_default(address(loan)), "Should fail to trigger default by commoner"); // Failed because commoner in not allowed to default the loan till the extendedGracePeriod passed.
        assertEq(loan.loanState(), 1,                       "Loan State should remain `Active`");

        hevm.warp(loan.nextPaymentDue() + 1);

        assertTrue(!bob.try_trigger_default(address(loan)),  "Still fails to default the loan by lender");   // Failed because still loan has gracePeriod to repay the dues.
        assertEq(loan.loanState(), 1,                        "Loan State should remain `Active`");
        assertTrue(!com.try_trigger_default(address(loan)),  "Still fails to default the loan by commoner"); // Failed because still commoner is not allowed to default the loan.
        assertEq(loan.loanState(), 1,                        "Loan State should remain `Active`");

        hevm.warp(loan.nextPaymentDue() + globals.gracePeriod());

        assertTrue(!bob.try_trigger_default(address(loan)),  "Still fails to default the loan by lender");   // Failed because still loan has gracePeriod to repay the dues.
        assertEq(loan.loanState(), 1,                        "Loan State should remain `Active`");
        assertTrue(!com.try_trigger_default(address(loan)),  "Still fails to default the loan by commoner"); // Failed because still commoner is not allowed to default the loan.
        assertEq(loan.loanState(), 1,                        "Loan State should remain `Active`");

        hevm.warp(loan.nextPaymentDue() + globals.gracePeriod() + 1);

        assertTrue(bob.try_trigger_default(address(loan)),  "Should not fail to default the loan");
        assertEq(loan.loanState(), 4,                       "Loan State should change to `Liquidated`");
    }

    function test_trigger_default_by_commoner() external  {
        ILoan loan = ILoan(address(createAndFundLoan(address(repaymentCalc))));

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(5000 * USD);
        ali.approve(WETH, address(loan), reqCollateral);

        assertTrue(ali.try_drawdown(address(loan), 5000 * USD));  // Draw down the loan.

        hevm.warp(loan.nextPaymentDue() + globals.gracePeriod() + globals.extendedGracePeriod());

        assertTrue(!com.try_trigger_default(address(loan)), "Should fail to trigger default by commoner"); // Failed because commoner in not allowed to default the loan till the extendedGracePeriod passed.
        assertEq(loan.loanState(), 1,                       "Loan State should remain `Active`");

        hevm.warp(loan.nextPaymentDue() + globals.gracePeriod() + globals.extendedGracePeriod() + 1);

        assertTrue(com.try_trigger_default(address(loan)), "Should not fail to default the loan");
        assertEq(loan.loanState(), 4,                      "Loan State should change to `Liquidated`");
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

        IERC20Details collateralAsset = loan.collateralAsset();
        uint256 _delta                = collateralAsset.balanceOf(address(ali));
        uint256 _usdcDelta            = IERC20(USDC).balanceOf(address(loan));

        // Make payment.
        assertTrue(ali.try_makeFullPayment(address(loan)));

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
}
