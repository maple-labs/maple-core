// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../LoanFactory.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";
import "../Loan.sol";
import "../DebtLockerFactory.sol";
import "../DebtLocker.sol";
import "../MapleToken.sol";
import "../MapleGlobals.sol";

contract InterestCalc {
    bytes32 public calcType = 'INTEREST';

    constructor() public {}
}

contract DebtLockerFactoryTest is TestUtil {

    MapleToken                      mpl;
    MapleGlobals                globals;
    FundingLockerFactory      flFactory;
    CollateralLockerFactory   clFactory;
    LoanFactory                lFactory;
    Loan                           loan;
    DebtLockerFactory         dlFactory;

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

        // Step 6: Set LF in the valid list of LF factories.
        globals.setValidLoanFactory(address(lFactory), true);

        // Step 7: Set valid factories i.e FLF & CLF under the LF.
        globals.setValidSubFactory(address(lFactory), address(flFactory), true);
        globals.setValidSubFactory(address(lFactory), address(clFactory), true);

        // Step 8: Deploy the Interest calc contract.
        address interestCalc = address(new InterestCalc());
        // Step 9: Deploy the LateFee calc contract.
        address lateFeeCalc  = address(new LateFeeCalc(uint256(5)));
        // Step 10: Deploy the Premium calc contract.
        address premiumCalc  = address(new PremiumCalc(uint256(5)));

        address[3] memory calcs = [interestCalc, lateFeeCalc, premiumCalc];

        // Step 11: Add calc contracts in valid list.
        for (uint8 i = 0; i < calcs.length; i++) {
            globals.setCalc(address(calcs[i]), true);
        }

        // Step 12: Add loan & collateral asset in to the valid list.
        globals.setLoanAsset(USDC, true);
        globals.setCollateralAsset(WETH, true);

        // Step 13: Create specs for a loan.
        uint256[6] memory specs = [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 5];

        // Step 14: Create loan using LF.
        loan        = Loan(lFactory.createLoan(USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        
        assertEq(lFactory.loansCreated(), 1, "Incorrect loan instantiation");       // Should be incrementer by 1.
        assertTrue(lFactory.isLoan(address(loan)));                                 // Should be considered as a loan.

        // Step 15: Create DLF.
        dlFactory   = new DebtLockerFactory();
    }

    function test_newLocker() public {
        DebtLocker dl  = DebtLocker(dlFactory.newLocker(address(loan)));
        // Validate the storage of dlfactory.
        assertEq(dlFactory.owner(address(dl)), address(this));
        assertTrue(dlFactory.isLocker(address(dl)));

        // Validate whether the dl has a DebtLocker interface or not.
        assertEq(dl.loan(), address(loan), "Incorrect loan address");
        assertEq(dl.owner(), address(this), "Incorrect owner of the DebtLocker");
        assertEq(dl.loanAsset(), USDC, "Incorrect address of loan asset");
    }

    
}
