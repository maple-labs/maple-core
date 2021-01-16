// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";
import "../LoanFactory.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";
import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../interfaces/ILoan.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

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

    MapleToken                      mpl;
    MapleGlobals                globals;
    FundingLockerFactory      flFactory;
    CollateralLockerFactory   clFactory;
    LoanFactory                lFactory;
    ILoan                          loan;
    Borrower                   borrower;

    uint256 constant MULTIPLIER = 10 ** 6;

    function setUp() public {
        // Step 1: Setup Maple token.
        mpl         = new MapleToken("MapleToken", "MAPL", USDC);
        // Step 2: Setup Maple Globals.
        globals     = new MapleGlobals(address(this), address(mpl), BPOOL_FACTORY);
        // Step 3: Setup Funding Locker Factory to support Loan Factory creation.
        flFactory   = new FundingLockerFactory();
        // Step 4: Setup Collateral Locker Factory to support Loan Factory creation.
        clFactory   = new CollateralLockerFactory();
        // Step 5: Setup Loan Factory to support Loan creation.
        lFactory    = new LoanFactory(address(globals));
        // Step 6: Create borrower.
        borrower    = new Borrower();
    }

    function set_calc() public returns (address[3] memory calcs) {
        address interestCalc = address(new InterestCalc());
        address lateFeeCalc  = address(new LateFeeCalc(uint256(5)));
        address premiumCalc  = address(new PremiumCalc(uint256(5)));

        calcs = [interestCalc, lateFeeCalc, premiumCalc];

        for (uint8 i = 0; i < calcs.length; i++) {
            globals.setCalc(address(calcs[i]), true);
        }
    }

    function set_valid_factories() public {
        globals.setValidLoanFactory(address(lFactory), true);
        globals.setValidSubFactory(address(lFactory), address(flFactory), true);
        globals.setValidSubFactory(address(lFactory), address(clFactory), true);
    }

    function test_createLoan_invalid_locker_factories() public {
        address[3] memory calcs = set_calc();
        globals.setLoanAsset(USDC, true);
        globals.setCollateralAsset(WETH, true);

        uint256[6] memory specs = [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 5];

        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // Add flFactory in valid list
        globals.setValidLoanFactory(address(lFactory), true);
        globals.setValidSubFactory(address(lFactory), address(flFactory), true);

        // Still fails as clFactory isn't a valid factory.
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.
        
        // Add clFactory in the valid list.
        globals.setValidSubFactory(address(lFactory), address(clFactory), true);

        // Should successfully created
        assertTrue(borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 1, "Incorrect loan instantiation");       // Should be incrementer by 1.
    }

    function test_createLoan_invalid_clac_types() public {
        set_valid_factories();
        address[3] memory calcs = set_calc();
        globals.setLoanAsset(USDC, true);
        globals.setCollateralAsset(WETH, true);

        uint256[6] memory specs = [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 5];

        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, [calcs[1], calcs[1], calcs[2]]));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // Incorrect type for second calculator contract.
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, [calcs[0], calcs[2], calcs[2]]));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // Incorrect type for third calculator contract.
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, [calcs[0], calcs[1], calcs[0]]));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // Should successfully created
        assertTrue(borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 1, "Incorrect loan instantiation");       // Should be incrementer by 1.
    }

    function test_createLoan_invalid_assets_and_specs() public {
        set_valid_factories();
        address[3] memory calcs = set_calc();
        uint256[6] memory specs = [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 5];

        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // Whitelist loan asset
        globals.setLoanAsset(USDC, true);
        // Still fails as collateral asset is not a valid collateral asset
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // Set collateral asset
        globals.setCollateralAsset(WETH, true);
        // Still fails as loan asset can't be 0x0
        assertTrue(!borrower.try_createPool(address(lFactory), address(0), WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // Fails because of error - ERR_PAYMENT_INTERVAL_DAYS_EQUALS_ZERO
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), [10, 10, 0, 10_000_000 * MULTIPLIER, 30, 5], calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // fails because of error - ERR_INVALID_TERM_AND_PAYMENT_INTERVAL_DIVISION
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), [10, 19, 2, 10_000_000 * MULTIPLIER, 30, 5], calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // fails because of error - ERR_MIN_RAISE_EQUALS_ZERO
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), [uint256(10), 10, 2, uint256(0), 30, 5], calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // fails because of error - ERR_FUNDING_PERIOD_EQUALS_ZERO
        assertTrue(!borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 0], calcs));
        assertEq(lFactory.loansCreated(), 0, "Colluded state");                     // Should be 0.

        // Should successfully created
        assertTrue(borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 1, "Incorrect loan instantiation");       // Should be incrementer by 1.
    }

    function test_createLoan_successfully() public {
        set_valid_factories();
        address[3] memory calcs = set_calc();
        globals.setLoanAsset(USDC, true);
        globals.setCollateralAsset(WETH, true);

        uint256[6] memory specs = [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 5];

        // Verify the loan gets created successfully.
        assertTrue(borrower.try_createPool(address(lFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(lFactory.loansCreated(), 1, "Incorrect loan instantiation");       // Should be incrementer by 1.
        ILoan loan   = ILoan(lFactory.loans(0));                                      // Intital value of loansCreated.
        assertTrue(lFactory.isLoan(address(loan)));                                 // Should be considered as a loan.

        // Verify the storage of loan contract
        assertEq(loan.borrower(),               address(borrower));
        assertEq(loan.loanAsset(),              USDC);
        assertEq(loan.collateralAsset(),        WETH);
        assertEq(loan.flFactory(),              address(flFactory));
        assertEq(loan.clFactory(),              address(clFactory));
        assertEq(loan.globals(),                address(globals));
        assertEq(loan.createdAt(),              block.timestamp);
        assertEq(loan.apr(),                    specs[0]);
        assertEq(loan.termDays(),               specs[1]);
        assertEq(loan.paymentsRemaining(),      specs[1].div(specs[2]));
        assertEq(loan.paymentIntervalSeconds(), specs[2].mul(1 days));
        assertEq(loan.minRaise(),               specs[3]);
        assertEq(loan.collateralRatio(),        specs[4]);
        assertEq(loan.fundingPeriodSeconds(),   specs[5].mul(1 days));
        assertEq(loan.repaymentCalc(),          calcs[0]);
        assertEq(loan.lateFeeCalc(),            calcs[1]);
        assertEq(loan.premiumCalc(),            calcs[2]);
        assertEq(loan.nextPaymentDue(),         (loan.createdAt()).add(loan.paymentIntervalSeconds()));
        assertEq(loan.superFactory(),           address(lFactory));
    }

    
}
