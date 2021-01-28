// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../BulletRepaymentCalc.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../LoanFactory.sol";

import "../interfaces/ILoan.sol";
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

    function triggerDefault(address loan) external {
        ILoan(loan).triggerDefault();
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

contract LoanLiquidationsTest is TestUtil {

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

        mpl         = new MapleToken("MapleToken", "MAPL", USDC);
        globals     = new MapleGlobals(address(this), address(mpl), BPOOL_FACTORY);
        flFactory   = new FundingLockerFactory();
        clFactory   = new CollateralLockerFactory();
        ethOracle   = new DSValue();
        usdcOracle  = new DSValue();
        bulletCalc  = new BulletRepaymentCalc();
        lateFeeCalc = new LateFeeCalc(0);   // Flat 0% fee
        premiumCalc = new PremiumCalc(500); // Flat 5% premium
        loanFactory = new LoanFactory(address(globals));

        ethOracle.poke(1334.61 ether);  // Set ETH price to $1377.61 TODO: Use chainlink in tests
        usdcOracle.poke(1 ether);   // Set USDC price to $1

        globals.setCalc(address(bulletCalc),         true);
        globals.setCalc(address(lateFeeCalc),        true);
        globals.setCalc(address(premiumCalc),        true);
        globals.setCollateralAsset(WETH,             true);
        globals.setLoanAsset(USDC,                   true);
        globals.assignPriceFeed(WETH,  address(ethOracle));
        globals.assignPriceFeed(USDC, address(usdcOracle));

        globals.setValidSubFactory(address(loanFactory), address(flFactory), true);
        globals.setValidSubFactory(address(loanFactory), address(clFactory), true);

        ali = new Borrower();
        bob = new Lender();
        trs = new Treasury();

        globals.setMapleTreasury(address(trs));

        mint("WETH", address(ali),   10 ether);
        mint("USDC", address(bob), 5000 * USD);
        mint("USDC", address(ali),  500 * USD);
    }

    function createAndFundLoan(address _interestStructure) internal returns (Loan loan) {
        uint256[6] memory specs = [500, 90, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [_interestStructure, address(lateFeeCalc), address(premiumCalc)];

        loan = ali.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        bob.approve(USDC, address(loan), 5000 * USD);

        bob.fundLoan(loan, 5000 * USD, address(ali));
        ali.approve(WETH, address(loan), 0.4 ether);
        assertTrue(ali.try_drawdown(address(loan), 1000 * USD));     // Borrow draws down 1000 USDC
    }

    function test_basic_liquidation() public {

        Loan loan = createAndFundLoan(address(bulletCalc));
        
        // Fetch pre-state variables.
        address collateralLocker  = loan.collateralLocker();
        address collateralAsset   = address(loan.collateralAsset());
        uint256 collateralBalance = IERC20(collateralAsset).balanceOf(address(collateralLocker));

        uint256 principalOwed_pre = loan.principalOwed();
        uint256 loanAssetLoan_pre  = IERC20(USDC).balanceOf(address(loan));
        uint256 loanAssetBorr_pre  = IERC20(USDC).balanceOf(address(ali));

        {
            // Fetch time variables.
            uint256 start          = block.timestamp;
            uint256 nextPaymentDue = loan.nextPaymentDue();
            uint256 gracePeriod    = globals.gracePeriod();

            // Warp to late payment.
            hevm.warp(start + nextPaymentDue + gracePeriod + 1);
        }

        // Pre-state triggerDefault() checks.
        assertEq(uint256(loan.loanState()),                                                     1);
        assertEq(IERC20(collateralAsset).balanceOf(address(collateralLocker)),  collateralBalance);

        loan.triggerDefault();

        {
            uint256 principalOwed_post   = loan.principalOwed();
            uint256 loanAssetLoan_post   = IERC20(USDC).balanceOf(address(loan));
            uint256 loanAssetBorr_post   = IERC20(USDC).balanceOf(address(ali));
            uint256 amountLiquidated     = loan.amountLiquidated();
            uint256 amountRecovered      = loan.amountRecovered();
            uint256 liquidationShortfall = loan.liquidationShortfall();
            uint256 liquidationExcess    = loan.liquidationExcess();

            // Post-state triggerDefault() checks.
            assertEq(uint256(loan.loanState()),                                     3);
            assertEq(IERC20(collateralAsset).balanceOf(address(collateralLocker)),  0);

            if (principalOwed_pre < amountRecovered) {
                assertEq(loanAssetBorr_post - loanAssetBorr_pre, liquidationExcess);
                assertEq(principalOwed_post,                                     0);
                assertEq(liquidationExcess,    amountRecovered - principalOwed_pre);
            }
            else {
                assertEq(principalOwed_post,   principalOwed_pre -amountRecovered);
                assertEq(liquidationShortfall,                 principalOwed_post);
                assertEq(liquidationExcess,                                     0);
            }
        }
    }
}