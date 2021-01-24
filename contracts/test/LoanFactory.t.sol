// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

import "../interfaces/ILoan.sol";

import "./user/Governor.sol";

import "../LoanFactory.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";
import "../MapleToken.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";


contract Borrower {
    function try_createPool(
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
        string memory sig = "createLoan(address,address,address,address,uint256[6],address[3])";
        (ok,) = address(loanFactory).call(
            abi.encodeWithSignature(sig, loanAsset, collateralAsset, flFactory, clFactory, specs, calcs)
        );
    }
}

contract InterestCalc {
    bytes32 public calcType = 'INTEREST';

    constructor() public {}
}

contract LoanFactoryTest is TestUtil {

    using SafeMath for uint256;

    Governor                        gov;
    MapleToken                      mpl;
    MapleGlobals                globals;
    FundingLockerFactory      flFactory;
    CollateralLockerFactory   clFactory;
    LoanFactory                lFactory;
    ILoan                          loan;
    Borrower                   borrower;

    uint256 constant MULTIPLIER = 10 ** 6;

    function setUp() public {
        gov       = new Governor();
        mpl       = new MapleToken("MapleToken", "MAPL", USDC);      // Setup Maple token.
        globals   = gov.createGlobals(address(mpl), BPOOL_FACTORY);  // Setup Maple Globals.
        flFactory = new FundingLockerFactory();                      // Setup Funding Locker Factory to support Loan Factory creation.
        clFactory = new CollateralLockerFactory();                   // Setup Collateral Locker Factory to support Loan Factory creation.
        lFactory  = new LoanFactory(address(globals));               // Setup Loan Factory to support Loan creation.
        borrower  = new Borrower();                                  // Create borrower.
    }

    function set_calcs() public returns (address[3] memory calcs) {
        address interestCalc = address(new InterestCalc());
        address lateFeeCalc  = address(new LateFeeCalc(uint256(5)));
        address premiumCalc  = address(new PremiumCalc(uint256(5)));

        calcs = [interestCalc, lateFeeCalc, premiumCalc];

        for (uint8 i = 0; i < calcs.length; i++) {
            gov.setCalc(address(calcs[i]), true);
        }
    }

    function set_valid_factories() public {
        gov.setValidLoanFactory(address(lFactory), true);
        gov.setValidSubFactory(address(lFactory), address(flFactory), true);
        gov.setValidSubFactory(address(lFactory), address(clFactory), true);
    }

    function test_createLoan_invalid_locker_factories() public {
        address[3] memory calcs = set_calcs();
        gov.setLoanAsset(USDC, true);
        gov.setCollateralAsset(WETH, true);

        uint256[6] memory specs = [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 5];

        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Add flFactory in valid list
        gov.setValidLoanFactory(address(lFactory), true);
        gov.setValidSubFactory(address(lFactory), address(flFactory), true);

        // Still fails as clFactory isn't a valid factory.
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.
        gov.setValidSubFactory(address(lFactory), address(clFactory), true);  // Add clFactory in the valid list.

        // Should successfully created
        assertTrue(borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 1, "Incorrect loan instantiation");  // Should be incremented by 1.
    }

    function test_createLoan_invalid_calc_types() public {
        set_valid_factories();
        address[3] memory calcs = set_calcs();
        gov.setLoanAsset(USDC, true);
        gov.setCollateralAsset(WETH, true);

        uint256[6] memory specs = [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 5];

        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, [calcs[1], calcs[1], calcs[2]]));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Incorrect type for second calculator contract.
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, [calcs[0], calcs[2], calcs[2]]));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Incorrect type for third calculator contract.
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, [calcs[0], calcs[1], calcs[0]]));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Should successfully created
        assertTrue(borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 1, "Incorrect loan instantiation");  // Should be incremented by 1.
    }

    function test_createLoan_invalid_assets_and_specs() public {
        set_valid_factories();
        address[3] memory calcs = set_calcs();
        uint256[6] memory specs = [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 5];

        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        gov.setLoanAsset(USDC, true);  // Whitelist loan asset
        // Still fails as collateral asset is not a valid collateral asset
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        gov.setCollateralAsset(WETH, true);  // Set collateral asset.
        // Still fails as loan asset can't be 0x0
        assertTrue(!borrower.try_createPool(address(lFactory), address(0), WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Fails because of error - ERR_PAYMENT_INTERVAL_DAYS_EQUALS_ZERO
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), [10, 10, 0, 10_000_000 * MULTIPLIER, 30, 5], calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Fails because of error - ERR_INVALID_TERM_AND_PAYMENT_INTERVAL_DIVISION
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), [10, 19, 2, 10_000_000 * MULTIPLIER, 30, 5], calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Fails because of error - ERR_MIN_RAISE_EQUALS_ZERO
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), [uint256(10), 10, 2, uint256(0), 30, 5], calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // fails because of error - ERR_FUNDING_PERIOD_EQUALS_ZERO
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 0], calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Should successfully created
        assertTrue(borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 1, "Incorrect loan instantiation");  // Should be incremented by 1.
    }

    function test_createLoan_successfully() public {
        set_valid_factories();
        address[3] memory calcs = set_calcs();
        gov.setLoanAsset(USDC, true);
        gov.setCollateralAsset(WETH, true);

        uint256[6] memory specs = [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 5];

        // Verify the loan gets created successfully.
        assertTrue(borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 1, "Incorrect loan instantiation");  // Should be incremented by 1.
        ILoan loan = ILoan(lFactory.loans(0));                                 // Intital value of loansCreated.
        assertTrue(lFactory.isLoan(address(loan)));                            // Should be considered as a loan.

        // Verify the storage of loan contract
        assertEq(loan.borrower(),                  address(borrower), "Incorrect borrower");
        assertEq(address(loan.loanAsset()),        USDC, "Incorrect loan asset");
        assertEq(address(loan.collateralAsset()),  WETH, "Incorrect collateral asset");
        assertEq(loan.flFactory(),                 address(flFactory), "Incorrect FLF");
        assertEq(loan.clFactory(),                 address(clFactory), "Incorrect CLF");
        assertEq(address(loan.globals()),          address(globals), "Incorrect globals address");
        assertEq(loan.createdAt(),                 block.timestamp, "Incorrect created at timestamp");
        assertEq(loan.apr(),                       specs[0], "Incorrect APR");
        assertEq(loan.termDays(),                  specs[1], "Incorrect term days");
        assertEq(loan.paymentsRemaining(),         specs[1].div(specs[2]), "Incorrect payments remaining");
        assertEq(loan.paymentIntervalSeconds(),    specs[2].mul(1 days), "Incorrect payment interval in seconds");
        assertEq(loan.minRaise(),                  specs[3], "Incorrect minimum raise value");
        assertEq(loan.collateralRatio(),           specs[4], "Incorrect collateral ratio");
        assertEq(loan.fundingPeriodSeconds(),      specs[5].mul(1 days), "Incorrect funding period in seconds");
        assertEq(loan.repaymentCalc(),             calcs[0], "Incorrect repayment calculator");
        assertEq(loan.lateFeeCalc(),               calcs[1], "Incorrect late fee calculator");
        assertEq(loan.premiumCalc(),               calcs[2], "Incorrect premium calculator");
        assertEq(loan.nextPaymentDue(),            (loan.createdAt()).add(loan.paymentIntervalSeconds()), "Incorrect next payment due timestamp");
        assertEq(loan.superFactory(),              address(lFactory), "Incorrect super factory address");
    }
}
