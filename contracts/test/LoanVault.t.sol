pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../calculators/BulletRepaymentCalculator.sol";
import "../calculators/LateFeeNullCalculator.sol";
import "../calculators/PremiumFlatCalculator.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../LoanVaultFactory.sol";

contract Borrower {
    function try_drawdown(address loanVault, uint256 amt) external returns (bool ok) {
        string memory sig = "drawdown(uint256)";
        (ok,) = address(loanVault).call(abi.encodeWithSignature(sig, amt));
    }

    function try_makePayment(address loanVault) external returns (bool ok) {
        string memory sig = "makePayment()";
        (ok,) = address(loanVault).call(abi.encodeWithSignature(sig));
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function createLoanVault(
        LoanVaultFactory loanVaultFactory,
        address requestedAsset, 
        address collateralAsset, 
        uint256[6] memory specifications,
        bytes32[3] memory calculators
    ) 
        external returns (LoanVault loanVault) 
    {
        loanVault = LoanVault(
            loanVaultFactory.createLoanVault(requestedAsset, collateralAsset, specifications, calculators)
        );
    }
}

contract Lender {
    function fundLoan(LoanVault loanVault, uint256 amt, address who) external {
        loanVault.fundLoan(amt, who);
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    // To assert failures
    function try_drawdown(address loanVault, uint256 amt) external returns (bool ok) {
        string memory sig = "drawdown(uint256)";
        (ok,) = address(loanVault).call(abi.encodeWithSignature(sig, amt));
    }
}

contract Treasury { }

contract LoanVaultTest is TestUtil {

    ERC20                     fundsToken;
    MapleToken                mapleToken;
    MapleGlobals              globals;
    FundingLockerFactory      fundingLockerFactory;
    CollateralLockerFactory   collateralLockerFactory;
    DSValue                   ethOracle;
    DSValue                   daiOracle;
    BulletRepaymentCalculator bulletCalc;
    LateFeeNullCalculator     lateFeeCalc;
    PremiumFlatCalculator     premiumCalc;
    LoanVaultFactory          loanVaultFactory;
    Borrower                  ali;
    Lender                    bob;
    Treasury                  trs;

    function setUp() public {

        fundsToken              = new ERC20("FundsToken", "FT");
        mapleToken              = new MapleToken("MapleToken", "MAPL", IERC20(fundsToken));
        globals                 = new MapleGlobals(address(this), address(mapleToken));
        fundingLockerFactory    = new FundingLockerFactory();
        collateralLockerFactory = new CollateralLockerFactory();
        ethOracle               = new DSValue();
        daiOracle               = new DSValue();
        bulletCalc              = new BulletRepaymentCalculator();
        lateFeeCalc             = new LateFeeNullCalculator();
        premiumCalc             = new PremiumFlatCalculator(500); // Flat 5% premium
        loanVaultFactory        = new LoanVaultFactory(
            address(globals), 
            address(fundingLockerFactory), 
            address(collateralLockerFactory)
        );

        ethOracle.poke(500 ether);  // Set ETH price to $600
        daiOracle.poke(1 ether);    // Set DAI price to $1

        globals.setInterestStructureCalculator("BULLET", address(bulletCalc));
        globals.setLateFeeCalculator("NULL", address(lateFeeCalc));
        globals.setPremiumCalculator("FLAT", address(premiumCalc));
        globals.addCollateralToken(WETH);
        globals.addBorrowToken(DAI);
        globals.assignPriceFeed(WETH, address(ethOracle));
        globals.assignPriceFeed(DAI, address(daiOracle));

        ali = new Borrower();
        bob = new Lender();
        trs = new Treasury();
        globals.setMapleTreasury(address(trs));

        mint("WETH", address(ali), 10 ether);
        mint("DAI",  address(bob), 5000 ether);
    }

    function test_createLoanVault() public {
        uint256[6] memory specifications = [500, 90, 30, uint256(1000 ether), 2000, 7];
        bytes32[3] memory calculators = [bytes32("BULLET"), bytes32("NULL"), bytes32("FLAT")];

        LoanVault loanVault = ali.createLoanVault(loanVaultFactory, DAI, WETH, specifications, calculators);
    
        assertEq(loanVault.assetRequested(),               DAI);
        assertEq(loanVault.assetCollateral(),              WETH);
        assertEq(loanVault.fundingLockerFactory(),         address(fundingLockerFactory));
        assertEq(loanVault.collateralLockerFactory(),      address(collateralLockerFactory));
        assertEq(loanVault.borrower(),                     address(ali));
        assertEq(loanVault.loanCreatedTimestamp(),         block.timestamp);
        assertEq(loanVault.aprBips(),                      specifications[0]);
        assertEq(loanVault.termDays(),                     specifications[1]);
        assertEq(loanVault.numberOfPayments(),             specifications[1] / specifications[2]);
        assertEq(loanVault.paymentIntervalSeconds(),       specifications[2] * 1 days);
        assertEq(loanVault.minRaise(),                     specifications[3]);
        assertEq(loanVault.collateralBipsRatio(),          specifications[4]);
        assertEq(loanVault.fundingPeriodSeconds(),         specifications[5] * 1 days);
        assertEq(address(loanVault.repaymentCalculator()), address(bulletCalc));
        assertEq(address(loanVault.lateFeeCalculator()),   address(lateFeeCalc));
        assertEq(address(loanVault.premiumCalculator()),   address(premiumCalc));
        assertEq(loanVault.nextPaymentDue(),               block.timestamp + loanVault.paymentIntervalSeconds());
    }

    function test_fundLoan() public {
        uint256[6] memory specifications = [500, 90, 30, uint256(1000 ether), 2000, 7];
        bytes32[3] memory calculators = [bytes32("BULLET"), bytes32("NULL"), bytes32("FLAT")];

        LoanVault loanVault = ali.createLoanVault(loanVaultFactory, DAI, WETH, specifications, calculators);
        address fundingLocker = loanVault.fundingLocker();

        bob.approve(DAI, address(loanVault), 5000 ether);
    
        assertEq(IERC20(loanVault).balanceOf(address(ali)),              0);
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),          0);
        assertEq(IERC20(DAI).balanceOf(address(bob)),           5000 ether);

        bob.fundLoan(loanVault, 5000 ether, address(ali));

        assertEq(IERC20(loanVault).balanceOf(address(ali)),     5000 ether);
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 5000 ether);
        assertEq(IERC20(DAI).balanceOf(address(bob)),                    0);
    }

    function createAndFundLoan() internal returns (LoanVault loanVault) {
        uint256[6] memory specifications = [500, 90, 30, uint256(1000 ether), 2000, 7];
        bytes32[3] memory calculators = [bytes32("BULLET"), bytes32("NULL"), bytes32("FLAT")];

        loanVault = ali.createLoanVault(loanVaultFactory, DAI, WETH, specifications, calculators);

        bob.approve(DAI, address(loanVault), 5000 ether);
    
        bob.fundLoan(loanVault, 5000 ether, address(ali));
    }

    function test_collateralRequiredForDrawdown() public {
        LoanVault loanVault = createAndFundLoan();

        uint256 reqCollateral = loanVault.collateralRequiredForDrawdown(1000 ether);
        assertEq(reqCollateral, 0.4 ether);
    }

    function test_drawdown() public {
        LoanVault loanVault = createAndFundLoan();

        assertTrue(!bob.try_drawdown(address(loanVault), 1000 ether));  // Non-borrower can't drawdown
        assertTrue(!ali.try_drawdown(address(loanVault), 1000 ether));  // Can't drawdown without approving collateral

        ali.approve(WETH, address(loanVault), 0.4 ether);

        assertTrue(!ali.try_drawdown(address(loanVault), 1000 ether - 1));  // Can't drawdown less than minRaise
        assertTrue(!ali.try_drawdown(address(loanVault), 5000 ether + 1));  // Can't drawdown more than fundingLocker balance

        address fundingLocker = loanVault.fundingLocker();

        assertEq(IERC20(WETH).balanceOf(address(ali)),        10 ether);  // Borrower collateral balance
        assertEq(IERC20(loanVault).balanceOf(address(ali)), 5000 ether);  // Borrower loanVault token balance
        assertEq(IERC20(DAI).balanceOf(fundingLocker),      5000 ether);  // Funding locker reqAssset balance
        assertEq(IERC20(DAI).balanceOf(address(loanVault)),          0);  // Loan vault reqAsset balance
        assertEq(IERC20(DAI).balanceOf(address(ali)),                0);  // Lender reqAsset balance
        assertEq(loanVault.drawdownAmount(),                         0);  // Drawdown amount
        assertEq(loanVault.principalOwed(),                          0);  // Principal owed
        assertEq(uint256(loanVault.loanState()),                     0);  // Loan state: Live

        // Fee related variables pre-check.
        assertEq(loanVault.feePaid(),                                0);  // feePaid amount
        assertEq(loanVault.excessReturned(),                         0);  // excessReturned amount
        assertEq(IERC20(DAI).balanceOf(address(trs)),                0);  // Treasury reqAsset balance

        assertTrue(ali.try_drawdown(address(loanVault), 1000 ether));     // Borrow draws down 1000 DAI

        address collateralLocker = loanVault.collateralLocker();

        assertEq(IERC20(WETH).balanceOf(address(ali)),       9.6 ether);  // Borrower collateral balance
        assertEq(IERC20(WETH).balanceOf(collateralLocker),   0.4 ether);  // Collateral locker collateral balance
        assertEq(IERC20(loanVault).balanceOf(address(ali)), 5000 ether);  // Borrower loanVault token balance
        assertEq(IERC20(DAI).balanceOf(fundingLocker),               0);  // Funding locker reqAssset balance
        assertEq(IERC20(DAI).balanceOf(address(loanVault)), 4005 ether);  // Loan vault reqAsset balance
        assertEq(IERC20(DAI).balanceOf(address(ali)),        990 ether);  // Lender reqAsset balance
        assertEq(loanVault.drawdownAmount(),                1000 ether);  // Drawdown amount
        assertEq(loanVault.principalOwed(),                 1000 ether);  // Principal owed
        assertEq(uint256(loanVault.loanState()),                     1);  // Loan state: Active

        
        // Fee related variables post-check.
        assertEq(loanVault.feePaid(),                          5 ether);  // Drawdown amount
        assertEq(loanVault.excessReturned(),                4000 ether);  // Principal owed
        assertEq(IERC20(DAI).balanceOf(address(trs)),          5 ether);  // Treasury reqAsset balance

    }

    function test_makePayment() public {
        LoanVault loanVault = createAndFundLoan();

        assertEq(uint256(loanVault.loanState()), 0);  // Loan state: Live

        assertTrue(!ali.try_makePayment(address(loanVault)));  // Can't makePayment when State != Active

        ali.approve(WETH, address(loanVault), 0.4 ether);

        assertTrue(ali.try_drawdown(address(loanVault), 1000 ether));     // Borrow draws down 1000 DAI

        address collateralLocker = loanVault.collateralLocker();
        address fundingLocker    = loanVault.fundingLocker();

        assertEq(loanVault.nextPaymentDue(), block.timestamp + loanVault.paymentIntervalSeconds());

        hevm.warp(block.timestamp + loanVault.paymentIntervalSeconds()); // Warp to second that next payment is due
    }
}
