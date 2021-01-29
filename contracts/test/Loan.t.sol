// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "./user/Governor.sol";

import "../BulletRepaymentCalc.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";

import "../MapleToken.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../LoanFactory.sol";
import "../interfaces/IERC20Details.sol";

contract Borrower {
    function try_drawdown(address loan, uint256 amt) external returns (bool ok) {
        string memory sig = "drawdown(uint256)";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig, amt));
    }

    function try_makePayment(address loan) external returns (bool ok) {
        string memory sig = "makePayment()";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig));
    }

    function try_createLoan(
        address loanFactory,
        address loanAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[6] memory specs,
        address[3] memory calcs
    ) 
        external returns (bool ok) 
    {
        string memory sig = "createLoan(address,address,uint256[],address[])";
        (ok,) = address(loanFactory).call(
            abi.encodeWithSignature(sig, loanAsset, collateralAsset, flFactory, clFactory, specs, calcs)
        );
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
        external returns (Loan loan) 
    {
        loan = Loan(
            loanFactory.createLoan(loanAsset, collateralAsset, flFactory, clFactory, specs, calcs)
        );
    }
}

contract Lender {
    function fundLoan(Loan loan, uint256 amt, address who) external {
        loan.fundLoan(amt, who);
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    // To assert failures
    function try_drawdown(address loan, uint256 amt) external returns (bool ok) {
        string memory sig = "drawdown(uint256)";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig, amt));
    }
}

contract Treasury { }

contract LoanTest is TestUtil {

    Governor                         gov;
    ERC20                     fundsToken;
    MapleToken                       mpl;
    MapleGlobals                 globals;
    FundingLockerFactory       flFactory;
    CollateralLockerFactory    clFactory;
    DSValue                    ethOracle;
    DSValue                   usdcOracle;
    BulletRepaymentCalc       bulletCalc;
    LateFeeCalc              lateFeeCalc;
    PremiumCalc              premiumCalc;
    LoanFactory              loanFactory;
    Borrower                         ali;
    Lender                           bob;
    Treasury                         trs;

    function setUp() public {

        gov         = new Governor();
        mpl         = new MapleToken("MapleToken", "MAPL", USDC);
        globals     = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        flFactory   = new FundingLockerFactory();
        clFactory   = new CollateralLockerFactory();
        ethOracle   = new DSValue();
        usdcOracle  = new DSValue();
        bulletCalc  = new BulletRepaymentCalc();
        lateFeeCalc = new LateFeeCalc(0);   // Flat 0% fee
        premiumCalc = new PremiumCalc(500); // Flat 5% premium
        loanFactory = new LoanFactory(address(globals));

        ethOracle.poke(500 ether);  // Set ETH price to $500
        usdcOracle.poke(1 ether);   // Set USDC price to $1

        gov.setCalc(address(bulletCalc),         true);
        gov.setCalc(address(lateFeeCalc),        true);
        gov.setCalc(address(premiumCalc),        true);
        gov.setCollateralAsset(WETH,             true);
        gov.setLoanAsset(USDC,                   true);
        gov.assignPriceFeed(WETH,  address(ethOracle));
        gov.assignPriceFeed(USDC, address(usdcOracle));

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        ali = new Borrower();
        bob = new Lender();
        trs = new Treasury();

        gov.setMapleTreasury(address(trs));

        mint("WETH", address(ali),   10 ether);
        mint("USDC", address(bob), 5000 * USD);
        mint("USDC", address(ali),  500 * USD);
    }

    function test_createLoan() public {
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        // Can't create a loan with DAI since stakingAsset uses USDC.
        assertTrue(!ali.try_createLoan(address(loanFactory), DAI, WETH, address(flFactory), address(clFactory), specs, calcs));

        Loan loan = ali.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
    
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
        assertEq(loan.repaymentCalc(),             address(bulletCalc));
        assertEq(loan.lateFeeCalc(),               address(lateFeeCalc));
        assertEq(loan.premiumCalc(),               address(premiumCalc));
        assertEq(loan.nextPaymentDue(),            block.timestamp + loan.paymentIntervalSeconds());
    }

    function test_fundLoan() public {
        uint256[6] memory specs = [500, 90, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan loan = ali.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        address fundingLocker = loan.fundingLocker();

        bob.approve(USDC, address(loan), 5000 * USD);
    
        assertEq(IERC20(loan).balanceOf(address(ali)),                    0);
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),          0);
        assertEq(IERC20(USDC).balanceOf(address(bob)),           5000 * USD);

        bob.fundLoan(loan, 5000 * USD, address(ali));

        assertEq(IERC20(loan).balanceOf(address(ali)),           5000 ether);
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 5000 * USD);
        assertEq(IERC20(USDC).balanceOf(address(bob)),                    0);
    }

    function createAndFundLoan(address _interestStructure) internal returns (Loan loan) {
        uint256[6] memory specs = [500, 90, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [_interestStructure, address(lateFeeCalc), address(premiumCalc)];

        loan = ali.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        bob.approve(USDC, address(loan), 5000 * USD);
    
        bob.fundLoan(loan, 5000 * USD, address(ali));
    }

    function test_collateralRequiredForDrawdown() public {
        Loan loan = createAndFundLoan(address(bulletCalc));

        uint256 reqCollateral = loan.collateralRequiredForDrawdown(1000 * USD);
        assertEq(reqCollateral, 0.4 ether);
    }

    function test_drawdown() public {
        Loan loan = createAndFundLoan(address(bulletCalc));

        assertTrue(!bob.try_drawdown(address(loan), 1000 * USD));  // Non-borrower can't drawdown
        assertTrue(!ali.try_drawdown(address(loan), 1000 * USD));  // Can't drawdown without approving collateral

        ali.approve(WETH, address(loan), 0.4 ether);

        assertTrue(!ali.try_drawdown(address(loan), 1000 * USD - 1));  // Can't drawdown less than requestAmount
        assertTrue(!ali.try_drawdown(address(loan), 5000 * USD + 1));  // Can't drawdown more than fundingLocker balance

        address fundingLocker = loan.fundingLocker();
        uint pre = IERC20(USDC).balanceOf(address(ali));

        assertEq(IERC20(WETH).balanceOf(address(ali)),    10 ether);  // Borrower collateral balance
        assertEq(IERC20(loan).balanceOf(address(ali)),  5000 ether);  // Borrower loan token balance
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

        address collateralLocker = loan.collateralLocker();

        assertEq(IERC20(WETH).balanceOf(address(ali)),            9.6 ether);  // Borrower collateral balance
        assertEq(IERC20(WETH).balanceOf(collateralLocker),        0.4 ether);  // Collateral locker collateral balance
        assertEq(IERC20(loan).balanceOf(address(ali)),           5000 ether);  // Borrower loan token balance
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

    function test_makePaymentBullet() public {

        Loan loan = createAndFundLoan(address(bulletCalc));

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Live

        assertTrue(!ali.try_makePayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collatearl and drawdown loan.
        ali.approve(WETH, address(loan), 0.4 ether);
        assertTrue(ali.try_drawdown(address(loan), 1000 * USD));  // Borrow draws down 1000 USDC

        address collateralLocker = loan.collateralLocker();
        address fundingLocker    = loan.fundingLocker();

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
        assertEq(loan.principalOwed(),                    0);  // Final payment, all principal paid for Bullet
        assertEq(loan.principalPaid(),                 _pri);
        assertEq(loan.interestPaid(),              _int * 3);
        assertEq(loan.paymentsRemaining(),                0);
        assertEq(loan.nextPaymentDue(),                   0);

        // Collateral locker after state.
        assertEq(collateralAsset.balanceOf(collateralLocker),                      0);
        assertEq(collateralAsset.balanceOf(address(ali)),     _delta + reqCollateral);

    }
    
    function test_makePaymentLateBullet() public {
        Loan loan = createAndFundLoan(address(bulletCalc));

        assertEq(uint256(loan.loanState()), 0);  // Loan state: Live

        assertTrue(!ali.try_makePayment(address(loan)));  // Can't makePayment when State != Active

        // Approve collatearl and drawdown loan.
        ali.approve(WETH, address(loan), 0.4 ether);
        assertTrue(ali.try_drawdown(address(loan), 1000 * USD));  // Borrow draws down 1000 USDC

        address collateralLocker = loan.collateralLocker();
        address fundingLocker    = loan.fundingLocker();

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
        assertEq(loan.principalOwed(),                    0);  // Final payment, all principal paid for Bullet
        assertEq(loan.principalPaid(),                 _pri);
        assertEq(loan.interestPaid(),              _int * 3);
        assertEq(loan.paymentsRemaining(),                0);
        assertEq(loan.nextPaymentDue(),                   0);

        // Collateral locker after state.
        assertEq(collateralAsset.balanceOf(collateralLocker),  0);
        assertEq(collateralAsset.balanceOf(address(ali)),     _delta + reqCollateral);
    }
}
