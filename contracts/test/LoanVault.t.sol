pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-value/value.sol";

import "lib/openzeppelin-contracts/src/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/src/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../LoanVaultFactory.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract Borrower {

}

contract Lender {
    function fundLoan(LoanVault loanVault, uint256 amt, address who) external {
        loanVault.fundLoan(amt, who);
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }
}

contract LoanVaultTest is DSTest {

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 constant WAD = 10 ** 18;

    Hevm                    hevm;
    ERC20                   fundsToken;
    MapleToken              mapleToken;
    MapleGlobals            globals;
    FundingLockerFactory    fundingLockerFactory;
    CollateralLockerFactory collateralLockerFactory;
    DSValue                 ethOracle;
    DSValue                 daiOracle;
    LoanVaultFactory        loanVaultFactory;
    Borrower                ali;
    Lender                  bob;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    function setUp() public {

        hevm = Hevm(address(CHEAT_CODE));

        fundsToken              = new ERC20("FundsToken", "FT");
        mapleToken              = new MapleToken("MapleToken", "MAPL", IERC20(fundsToken));
        globals                 = new MapleGlobals(address(this), address(mapleToken));
        fundingLockerFactory    = new FundingLockerFactory();
        collateralLockerFactory = new CollateralLockerFactory();
        ethOracle               = new DSValue();
        daiOracle               = new DSValue();
        loanVaultFactory        = new LoanVaultFactory(
            address(globals), 
            address(fundingLockerFactory), 
            address(collateralLockerFactory)
        );

        ethOracle.poke(bytes32(500 * WAD));  // Set ETH price to $600
        daiOracle.poke(bytes32(1 * WAD));    // Set DAI price to $1

        globals.setInterestStructureCalculator("BULLET", address(1));  // Add dummy interest calculator
        globals.setLateFeeCalculator("NULL", address(2));  // Add dummy late fee calculator
        globals.setPremiumCalculator("FLAT", address(3));  // Add dummy premium calculator
        globals.addCollateralToken(WETH);
        globals.addBorrowToken(DAI);
        globals.assignPriceFeed(WETH, address(ethOracle));
        globals.assignPriceFeed(DAI, address(daiOracle));

        ali = new Borrower();
        bob = new Lender();

        // Mint 500 DAI into Bob's account
        assertEq(IERC20(DAI).balanceOf(address(bob)), 0);
        hevm.store(
            DAI,
            keccak256(abi.encode(address(bob), uint256(2))),
            bytes32(uint256(500 * WAD))
        );
        assertEq(IERC20(DAI).balanceOf(address(bob)), 500 * WAD);
    }

    function test_create_loan_vault() public {
        uint256[6] memory specifications = [500, 90, 30, uint256(1000 * WAD), 2000, 7];
        bytes32[3] memory calculators = [bytes32("BULLET"), bytes32("NULL"), bytes32("FLAT")];

        LoanVault loanVault = LoanVault(loanVaultFactory.createLoanVault(DAI, WETH, specifications, calculators));
    
        assertEq(loanVault.assetRequested(),               DAI);
        assertEq(loanVault.assetCollateral(),              WETH);
        assertEq(loanVault.fundingLockerFactory(),         address(fundingLockerFactory));
        assertEq(loanVault.collateralLockerFactory(),      address(collateralLockerFactory));
        assertEq(loanVault.borrower(),                     tx.origin);
        assertEq(loanVault.loanCreatedTimestamp(),         now);
        assertEq(loanVault.aprBips(),                      specifications[0]);
        assertEq(loanVault.termDays(),                     specifications[1]);
        assertEq(loanVault.numberOfPayments(),             specifications[1] / specifications[2]);
        assertEq(loanVault.paymentIntervalSeconds(),       specifications[2] * 1 days);
        assertEq(loanVault.minRaise(),                     specifications[3]);
        assertEq(loanVault.collateralBipsRatio(),          specifications[4]);
        assertEq(loanVault.fundingPeriodSeconds(),         specifications[5] * 1 days);
        assertEq(address(loanVault.repaymentCalculator()), address(1));
        assertEq(address(loanVault.lateFeeCalculator()),   address(2));
        assertEq(address(loanVault.premiumCalculator()),   address(3));
    }

    function test_fund_loan() public {
        uint256[6] memory specifications = [500, 90, 30, uint256(1000 * WAD), 2000, 7];
        bytes32[3] memory calculators = [bytes32("BULLET"), bytes32("NULL"), bytes32("FLAT")];

        LoanVault loanVault   = LoanVault(loanVaultFactory.createLoanVault(DAI, WETH, specifications, calculators));
        address fundingLocker = loanVault.fundingLocker();

        bob.approve(DAI, address(loanVault), 500 * WAD);
    
        assertEq(IERC20(loanVault).balanceOf(address(ali)), 0);
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 0);
        assertEq(IERC20(DAI).balanceOf(address(bob)), 500 * WAD);

        bob.fundLoan(loanVault, 500 * WAD, address(ali));

        assertEq(IERC20(loanVault).balanceOf(address(ali)), 500 * WAD);
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 500 * WAD);
        assertEq(IERC20(DAI).balanceOf(address(bob)), 0);
    }

    function test_collateral_required() public {
        uint256[6] memory specifications = [500, 90, 30, uint256(1000 * WAD), 2000, 7];
        bytes32[3] memory calculators = [bytes32("BULLET"), bytes32("NULL"), bytes32("FLAT")];

        LoanVault loanVault = LoanVault(loanVaultFactory.createLoanVault(DAI, WETH, specifications, calculators));

        bob.approve(DAI, address(loanVault), 500 * WAD);
    
        bob.fundLoan(loanVault, 500 * WAD, address(ali));

        uint256 reqCollateral = loanVault.collateralRequiredForDrawdown(500 * WAD);
        assertEq(reqCollateral, 0.2 ether);
    }
}
