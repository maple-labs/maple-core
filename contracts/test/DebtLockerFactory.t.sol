// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";
import "../LoanFactory.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";
import "../DebtLocker.sol";
import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../interfaces/ILoan.sol";
import "../DebtLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";

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
    ILoan                          loan;
    DebtLockerFactory         dlFactory;

    uint256 constant MULTIPLIER = 10 ** 6;

    function setUp() public {
        mpl       = new MapleToken("MapleToken", "MAPL", USDC);                    // Setup Maple token.
        globals   = new MapleGlobals(address(this), address(mpl), BPOOL_FACTORY);  // Setup Maple Globals.
        flFactory = new FundingLockerFactory();                                    // Setup Funding Locker Factory to support Loan Factory creation.
        clFactory = new CollateralLockerFactory();                                 // Setup Collateral Locker Factory to support Loan Factory creation.
        lFactory  = new LoanFactory(address(globals));                             // Setup Loan Factory to support Loan creation.

        globals.setValidLoanFactory(address(lFactory), true);                      // Set LF in the valid list of LF factories.
        globals.setValidSubFactory(address(lFactory), address(flFactory), true);   // Set valid factory i.e FLF under the LF.
        globals.setValidSubFactory(address(lFactory), address(clFactory), true);   // Set valid factory i.e CLF under the LF.

        address interestCalc = address(new InterestCalc());                        // Deploy the Interest calc contract.
        address lateFeeCalc  = address(new LateFeeCalc(uint256(5)));               // Deploy the LateFee calc contract.
        address premiumCalc  = address(new PremiumCalc(uint256(5)));               // Deploy the Premium calc contract.

        address[3] memory calcs = [interestCalc, lateFeeCalc, premiumCalc];
        for (uint8 i = 0; i < calcs.length; i++) {
            globals.setCalc(address(calcs[i]), true);
        }

        globals.setLoanAsset(USDC, true);        // Add loan asset in to the valid list.
        globals.setCollateralAsset(WETH, true);  // Add collateral asset into the valid list

        uint256[6] memory specs = [10, 10, 2, 10_000_000 * MULTIPLIER, 30, 5];                                // Create specs for a loan.
        loan = ILoan(lFactory.createLoan(USDC, WETH, address(flFactory), address(clFactory), specs, calcs));  // Create loan using LF.
        
        assertEq(lFactory.loansCreated(), 1, "Incorrect loan instantiation");  // Should be incrementer by 1.
        assertTrue(lFactory.isLoan(address(loan)));                            // Should be considered as a loan.
        dlFactory = new DebtLockerFactory();                                   // Create DLF.
        assertEq(dlFactory.factoryType(), uint(1), "Incorrect factory type");
    }

    function test_newLocker() public {
        DebtLocker dl  = DebtLocker(dlFactory.newLocker(address(loan)));
        // Validate the storage of dlfactory.
        assertEq(dlFactory.owner(address(dl)), address(this));
        assertTrue(dlFactory.isLocker(address(dl)));

        // Validate the storage of dl.
        assertEq(address(dl.loan()),      address(loan), "Incorrect loan address");
        assertEq(dl.owner(),     address(this), "Incorrect owner of the DebtLocker");
        assertEq(address(dl.loanAsset()), USDC, "Incorrect address of loan asset");
    }
}
