pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/ILiquidityPool.sol";
import "../interfaces/ILiquidityPoolFactory.sol";

import "../calculators/AmortizationRepaymentCalculator.sol";
import "../calculators/BulletRepaymentCalculator.sol";
import "../calculators/LateFeeNullCalculator.sol";
import "../calculators/PremiumFlatCalculator.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../StakeLockerFactory.sol";
import "../LiquidityPoolFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../LoanTokenLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../LoanVaultFactory.sol";
import "../LoanVault.sol";
import "../LiquidityPool.sol";

interface IBPoolFactory {
    function newBPool() external returns (address);
}

contract PoolDelegate {
    function try_fundLoan(address lp1, address vault, address ltlf1, uint256 amt) external returns (bool ok) {
        string memory sig = "fundLoan(address,address,uint256)";
        (ok,) = address(lp1).call(abi.encodeWithSignature(sig, vault, ltlf1, amt));
    }

    function createLiquidityPool(
        address liqPoolFactory, 
        address liqAsset,
        address stakeAsset,
        uint256 stakingFee,
        uint256 delegateFee,
        string memory name,
        string memory symbol
    ) 
        external returns (address liquidityPool) 
    {
        liquidityPool = ILiquidityPoolFactory(liqPoolFactory).createLiquidityPool(
            liqAsset,
            stakeAsset,
            stakingFee,
            delegateFee,
            name,
            symbol 
        );
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function claim(address lPool, address vault, address ltlf) external returns(uint, uint, uint, uint, uint) {
        ILiquidityPool(lPool).claim(vault, ltlf);  
    }
}

contract LP {
    function try_deposit(address lp1, uint256 amt)  external returns (bool ok) {
        string memory sig = "deposit(uint256)";
        (ok,) = address(lp1).call(abi.encodeWithSignature(sig, amt));
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function withdraw(address lPool, uint256 amt) external {
        LiquidityPool(lPool).withdraw(amt);
    }

    function withdraw(address lPool) external {
        LiquidityPool(lPool).withdraw();
    }
}

contract Borrower {

    // TODO: remove the try_* for LoanVault specific functions
    function try_drawdown(address loanVault, uint256 amt) external returns (bool ok) {
        string memory sig = "drawdown(uint256)";
        (ok,) = address(loanVault).call(abi.encodeWithSignature(sig, amt));
    }

    function try_makePayment(address loanVault) external returns (bool ok) {
        string memory sig = "makePayment()";
        (ok,) = address(loanVault).call(abi.encodeWithSignature(sig));
    }

    function makePayment(address loanVault) external {
        LoanVault(loanVault).makePayment();
    }

    function drawdown(address loanVault, uint256 _drawdownAmount) external {
        LoanVault(loanVault).drawdown(_drawdownAmount);
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

contract LiquidityPoolTest is TestUtil {

    ERC20                           fundsToken;
    MapleToken                      mapleToken;
    MapleGlobals                       globals;
    FundingLockerFactory             flFactory;
    CollateralLockerFactory          clFactory;
    LoanVaultFactory              loanVFactory;
    LoanVault                            vault;
    LoanVault                           vault2;
    LiquidityPoolFactory        liqPoolFactory;
    StakeLockerFactory           stakeLFactory;
    LiquidityLockerFactory         liqLFactory; 
    LoanTokenLockerFactory               ltlf1; 
    LoanTokenLockerFactory               ltlf2; 
    LiquidityPool                          lp1; 
    DSValue                          ethOracle;
    DSValue                          daiOracle;
    AmortizationRepaymentCalculator amortiCalc;
    BulletRepaymentCalculator       bulletCalc;
    LateFeeNullCalculator          lateFeeCalc;
    PremiumFlatCalculator          premiumCalc;
    IBPool                               bPool;
    PoolDelegate                           lpd;
    LP                                     bob;
    LP                                     che;
    LP                                     dan;
    Borrower                               eli;
    Borrower                               fay;

    function setUp() public {

        fundsToken     = new ERC20("FundsToken", "FT");
        mapleToken     = new MapleToken("MapleToken", "MAPL", IERC20(fundsToken));
        globals        = new MapleGlobals(address(this), address(mapleToken));
        flFactory      = new FundingLockerFactory();
        clFactory      = new CollateralLockerFactory();
        loanVFactory   = new LoanVaultFactory(address(globals), address(flFactory), address(clFactory));
        stakeLFactory  = new StakeLockerFactory();
        liqLFactory    = new LiquidityLockerFactory();
        liqPoolFactory = new LiquidityPoolFactory(address(globals), address(stakeLFactory), address(liqLFactory));
        ltlf1          = new LoanTokenLockerFactory();
        ltlf2          = new LoanTokenLockerFactory();
        ethOracle      = new DSValue();
        daiOracle      = new DSValue();
        amortiCalc     = new AmortizationRepaymentCalculator();
        bulletCalc     = new BulletRepaymentCalculator();
        lateFeeCalc    = new LateFeeNullCalculator();
        premiumCalc    = new PremiumFlatCalculator(500); // Flat 5% premium
        lpd            = new PoolDelegate();
        bob            = new LP();
        che            = new LP();
        dan            = new LP();
        eli            = new Borrower();
        fay            = new Borrower();

        ethOracle.poke(500 ether);  // Set ETH price to $600
        daiOracle.poke(1 ether);    // Set DAI price to $1

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * 10 ** 6);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), uint(-1));
        mapleToken.approve(address(bPool), uint(-1));

        bPool.bind(USDC, 50_000_000 * 10 ** 6, 5 ether);          // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mapleToken), 100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * 10 ** 6);
        assertEq(mapleToken.balanceOf(address(bPool)),   100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized

        globals.setPoolDelegateWhitelist(address(lpd), true);
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(lpd), bPool.balanceOf(address(this)));

        // Set Globals
        globals.setInterestStructureCalculator("AMORTIZATION", address(amortiCalc));
        globals.setInterestStructureCalculator("BULLET", address(bulletCalc));
        globals.setLateFeeCalculator("NULL", address(lateFeeCalc));
        globals.setPremiumCalculator("FLAT", address(premiumCalc));
        globals.addCollateralToken(WETH);
        globals.addBorrowToken(DAI);
        globals.assignPriceFeed(WETH, address(ethOracle));
        globals.assignPriceFeed(DAI, address(daiOracle));
        globals.setMapleBPool(address(bPool));
        globals.setMapleBPoolAssetPair(USDC);
        globals.setStakeRequired(100 * 10 ** 6);

        // Create Liquidity Pool
        lp1 = LiquidityPool(lpd.createLiquidityPool(
            address(liqPoolFactory),
            DAI,
            address(bPool),
            500,
            100,
            "Maple Liquidity Pool 0",
            "MPL_LP_0"
        ));

        // vault Specifications
        uint256[6] memory specs_vault = [500, 90, 30, uint256(1000 ether), 2000, 7];
        bytes32[3] memory calcs_vault = [bytes32("BULLET"), bytes32("NULL"), bytes32("FLAT")];

        // vault2 Specifications
        uint256[6] memory specs_vault2 = [500, 90, 30, uint256(1000 ether), 2000, 7];
        bytes32[3] memory calcs_vault2 = [bytes32("AMORTIZATION"), bytes32("NULL"), bytes32("FLAT")];

        vault  = eli.createLoanVault(loanVFactory, DAI, WETH, specs_vault, calcs_vault);
        vault2 = fay.createLoanVault(loanVFactory, DAI, WETH, specs_vault2, calcs_vault2);
    }

    function test_stake_and_finalize() public {
        address stakeLocker = lp1.stakeLockerAddress();

        lpd.approve(address(bPool), stakeLocker, uint(-1));
        assertEq(bPool.balanceOf(address(lpd)),               100 * WAD);
        assertEq(bPool.balanceOf(stakeLocker),                0);
        assertEq(IERC20(stakeLocker).balanceOf(address(lpd)), 0);

        lpd.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(lpd)) / 2);

        assertEq(bPool.balanceOf(address(lpd)),               50 * WAD);
        assertEq(bPool.balanceOf(stakeLocker),                50 * WAD);
        assertEq(IERC20(stakeLocker).balanceOf(address(lpd)), 50 * WAD);

        lp1.finalize();
    }

    function test_deposit() public {
        address stakeLocker = lp1.stakeLockerAddress();
        address liqLocker   = lp1.liquidityLockerAddress();

        lpd.approve(address(bPool), stakeLocker, uint(-1));
        lpd.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(lpd)) / 2);

        // Mint 100 DAI into this LP account
        mint("DAI", address(bob), 100 ether);

        assertTrue(!bob.try_deposit(address(lp1), 100 ether)); // Not finalized

        lp1.finalize();

        assertTrue(!bob.try_deposit(address(lp1), 100 ether)); // Not approved

        bob.approve(DAI, address(lp1), uint(-1));

        assertEq(IERC20(DAI).balanceOf(address(bob)), 100 ether);
        assertEq(IERC20(DAI).balanceOf(liqLocker),            0);
        assertEq(lp1.balanceOf(address(bob)),             0);

        assertTrue(bob.try_deposit(address(lp1), 100 ether));

        assertEq(IERC20(DAI).balanceOf(address(bob)),         0);
        assertEq(IERC20(DAI).balanceOf(liqLocker),    100 ether);
        assertEq(lp1.balanceOf(address(bob)),     100 ether);
    }

    function test_fundLoan() public {
        address stakeLocker   = lp1.stakeLockerAddress();
        address liqLocker     = lp1.liquidityLockerAddress();
        address fundingLocker = vault.fundingLocker();

        lpd.approve(address(bPool), stakeLocker, uint(-1));
        lpd.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(lpd)) / 2);

        // Mint 100 DAI into this LP account
        mint("DAI", address(bob), 100 ether);

        lp1.finalize();

        bob.approve(DAI, address(lp1), uint(-1));

        assertTrue(bob.try_deposit(address(lp1), 100 ether));

        assertTrue(!lpd.try_fundLoan(address(lp1), address(vault), address(ltlf1), 100 ether)); // LoanVaultFactory not in globals

        globals.setLoanVaultFactory(address(loanVFactory));

        assertEq(IERC20(DAI).balanceOf(liqLocker),               100 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),          0);  // Balance of Funding Locker
        
        /*******************/
        /*** Fund a Loan ***/
        /*******************/
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault), address(ltlf1), 20 ether));  // Fund loan for 20 DAI

        (
            address loanVaultFunded,
            address loanTokenLocker,
            uint256 amountFunded,
            uint256 principalPaid,
            uint256 interestPaid,
            uint256 feePaid,
            uint256 excessReturned
        ) = lp1.loans(address(vault), address(ltlf1));

        assertEq(ltlf1.lockers(0), loanTokenLocker);  // LTL instantiated

        assertEq(loanVaultFunded,  address(vault));
        assertEq(amountFunded,           20 ether); 
        assertEq(principalPaid,                 0);
        assertEq(interestPaid,                  0);
        assertEq(feePaid,                       0);
        assertEq(excessReturned,                0);

        assertEq(IERC20(DAI).balanceOf(liqLocker),              80 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 20 ether);  // Balance of Funding Locker
        assertEq(IERC20(vault).balanceOf(loanTokenLocker),      20 ether);  // LoanToken balance of LT Locker

        /****************************************/
        /*** Fund same loan with the same LTL ***/
        /****************************************/
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault), address(ltlf1), 25 ether)); // Fund loan for 25 DAI
        (
            loanVaultFunded,
            loanTokenLocker,
            amountFunded,
            principalPaid,
            interestPaid,
            feePaid,
            excessReturned
        ) = lp1.loans(address(vault), address(ltlf1));

        assertEq(ltlf1.lockers(0), loanTokenLocker);  // Same LTL

        assertEq(loanVaultFunded,  address(vault));
        assertEq(amountFunded,           45 ether); 
        assertEq(principalPaid,                 0);
        assertEq(interestPaid,                  0);
        assertEq(feePaid,                       0);
        assertEq(excessReturned,                0);

        assertEq(IERC20(DAI).balanceOf(liqLocker),              55 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 45 ether);  // Balance of Funding Locker
        assertEq(IERC20(vault).balanceOf(loanTokenLocker),      45 ether);  // LoanToken balance of LT Locker

        /*******************************************/
        /*** Fund same loan with a different LTL ***/
        /*******************************************/
        LoanTokenLockerFactory ltlf2 = new LoanTokenLockerFactory();
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault), address(ltlf2), 15 ether)); // Fund loan for 25 DAI

        (
            loanVaultFunded,
            loanTokenLocker,
            amountFunded,
            principalPaid,
            interestPaid,
            feePaid,
            excessReturned
        ) = lp1.loans(address(vault), address(ltlf2)); // Next struct in mapping, corrresponding to new LTL

        assertEq(ltlf2.lockers(0), loanTokenLocker);  // Same LTL

        assertEq(loanVaultFunded,  address(vault));
        assertEq(amountFunded,           15 ether); 
        assertEq(principalPaid,                 0);
        assertEq(interestPaid,                  0);
        assertEq(feePaid,                       0);
        assertEq(excessReturned,                0);

        assertEq(IERC20(DAI).balanceOf(liqLocker),              40 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 60 ether);  // Balance of Funding Locker
        assertEq(IERC20(vault).balanceOf(loanTokenLocker),      15 ether);  // LoanToken balance of LT Locker
    }

    function test_claim_singleLP() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        address stakeLocker = lp1.stakeLockerAddress();
        address liqLocker   = lp1.liquidityLockerAddress();

        lpd.approve(address(bPool), stakeLocker, uint(-1));
        lpd.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(lpd)) / 2);

        lp1.finalize();

        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        mint("DAI", address(bob), 10000 ether);
        mint("DAI", address(che), 10000 ether);
        mint("DAI", address(dan), 10000 ether);

        bob.approve(DAI, address(lp1), uint(-1));
        che.approve(DAI, address(lp1), uint(-1));
        dan.approve(DAI, address(lp1), uint(-1));

        assertTrue(bob.try_deposit(address(lp1), 1000 ether));  // 10%
        assertTrue(che.try_deposit(address(lp1), 3000 ether));  // 30%
        assertTrue(dan.try_deposit(address(lp1), 6000 ether));  // 60%

        globals.setLoanVaultFactory(address(loanVFactory)); // Don't remove, not done in setUp()

        address fundingLocker  = vault.fundingLocker();
        address fundingLocker2 = vault2.fundingLocker();

        /************************************/
        /*** Fund vault / vault2 (Excess) ***/
        /************************************/
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault),  address(ltlf1),   25 ether));  // Fund vault using ltlf1 for 25 DAI
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault),  address(ltlf1),   25 ether));  // Fund vault using ltlf1 for 25 DAI, again, 50 DAI total
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault),  address(ltlf2),   50 ether));  // Fund vault using ltlf2 for 50 DAI
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault),  address(ltlf2), 1000 ether));  // Fund vault using ltlf2 for 1000 DAI (excess), 1050 DAI total

        assertTrue(lpd.try_fundLoan(address(lp1), address(vault2), address(ltlf1),   20 ether));  // Fund vault2 using ltlf1 for 20 DAI
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault2), address(ltlf1),   20 ether));  // Fund vault2 using ltlf1 for 20 DAI, again 40 DAI total
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault2), address(ltlf2),   60 ether));  // Fund vault2 using ltlf2 for 60 DAI
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault2), address(ltlf2), 1000 ether));  // Fund vault2 using ltlf2 for 1000 DAI (excess), 1060 DAI total

        (,address ltl1,,,,,) = lp1.loans(address(vault),  address(ltlf1));  // ltl1 = LoanTokenLocker 1, for vault using ltlf1
        (,address ltl2,,,,,) = lp1.loans(address(vault),  address(ltlf2));  // ltl2 = LoanTokenLocker 2, for vault using ltlf2
        (,address ltl3,,,,,) = lp1.loans(address(vault2), address(ltlf1));  // ltl3 = LoanTokenLocker 3, for vault2 using ltlf1
        (,address ltl4,,,,,) = lp1.loans(address(vault2), address(ltlf2));  // ltl4 = LoanTokenLocker 4, for vault2 using ltlf2

        // Present state checks
        assertEq(IERC20(DAI).balanceOf(liqLocker),               7800 ether);  // 10000 DAI deposited - (1100 DAI + 1100 DAI)
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),  1100 ether);  // Balance of vault fl
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker2)), 1100 ether);  // Balance of vault2 fl
        assertEq(IERC20(vault).balanceOf(ltl1),                    50 ether);  // Balance of ltl1 for lp1 with ltlf1
        assertEq(IERC20(vault).balanceOf(ltl2),                  1050 ether);  // Balance of ltl2 for lp1 with ltlf2
        assertEq(IERC20(vault2).balanceOf(ltl3),                   40 ether);  // Balance of ltl3 for lp1 with ltlf1
        assertEq(IERC20(vault2).balanceOf(ltl4),                 1060 ether);  // Balance of ltl4 for lp1 with ltlf2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        uint cReq1 =  vault.collateralRequiredForDrawdown(1000 ether); // wETH required for 1000 DAI drawdown on vault
        uint cReq2 = vault2.collateralRequiredForDrawdown(1000 ether); // wETH required for 1000 DAI drawdown on vault2
        mint("WETH", address(eli), cReq1);
        mint("WETH", address(fay), cReq2);
        eli.approve(WETH, address(vault),  cReq1);
        fay.approve(WETH, address(vault2), cReq2);
        eli.drawdown(address(vault),  1000 ether);
        fay.drawdown(address(vault2), 1000 ether);
        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        (uint amt1_1,,,) =  vault.getNextPayment(); // DAI required for 1st payment on vault
        (uint amt1_2,,,) = vault2.getNextPayment(); // DAI required for 1st payment on vault2
        mint("DAI", address(eli), amt1_1);
        mint("DAI", address(fay), amt1_2);
        eli.approve(DAI, address(vault),  amt1_1);
        fay.approve(DAI, address(vault2), amt1_2);
        eli.makePayment(address(vault));
        fay.makePayment(address(vault2));
        
        /*****************/
        /***  LP Claim ***/
        /*****************/

        // Pre-state checks

        // LiquidityPool claim() across ltl1, ltl2, ltl3, ltl4
        lpd.claim(address(lp1), address(vault),  address(ltlf1));
        lpd.claim(address(lp1), address(vault),  address(ltlf2));
        lpd.claim(address(lp1), address(vault2), address(ltlf1));
        lpd.claim(address(lp1), address(vault2), address(ltlf2));

        // Post-state checks

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        
        /*****************/
        /***  LP Claim ***/
        /*****************/

    }

    function test_withdraw() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        address stakeLocker = lp1.stakeLockerAddress();
        address liqLocker   = lp1.liquidityLockerAddress();

        lpd.approve(address(bPool), stakeLocker, uint(-1));
        lpd.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(lpd)) / 2);

        lp1.finalize();

        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        mint("DAI", address(bob), 100 ether);
        mint("DAI", address(che), 100 ether);
        mint("DAI", address(dan), 100 ether);

        bob.approve(DAI, address(lp1), uint(-1));
        che.approve(DAI, address(lp1), uint(-1));
        dan.approve(DAI, address(lp1), uint(-1));

        assertTrue(bob.try_deposit(address(lp1), 10 ether));  // 10%
        assertTrue(che.try_deposit(address(lp1), 30 ether));  // 30%
        assertTrue(dan.try_deposit(address(lp1), 60 ether));  // 60%

        globals.setLoanVaultFactory(address(loanVFactory));

        /*******************************************/
        /*** Create new ltlf1 and LoanVault ***/
        /*******************************************/
        LoanTokenLockerFactory ltlf2 = new LoanTokenLockerFactory();

        // Create Loan Vault
        uint256[6] memory specs = [500, 90, 30, uint256(1000 ether), 2000, 7];
        bytes32[3] memory calcs = [bytes32("BULLET"), bytes32("NULL"), bytes32("FLAT")];

        LoanVault vault2 = LoanVault(loanVFactory.createLoanVault(DAI, WETH, specs, calcs));

        address fundingLocker  = vault.fundingLocker();
        address fundingLocker2 = vault2.fundingLocker();

        /******************/
        /*** Fund Loans ***/
        /******************/
        assertEq(IERC20(DAI).balanceOf(liqLocker),              100 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),         0);  // Balance of Funding Locker

        assertTrue(lpd.try_fundLoan(address(lp1), address(vault),  address(ltlf1),  20 ether));  // Fund loan for 20 DAI
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault),  address(ltlf1),  25 ether));  // Fund same loan for 25 DAI
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault),  address(ltlf2), 15 ether));  // Fund new loan same vault for 15 DAI
        assertTrue(lpd.try_fundLoan(address(lp1), address(vault2), address(ltlf2), 15 ether));  // Fund new loan new vault for 15 DAI

        (, address ltLocker,,,,,)  = lp1.loans(address(vault),  address(ltlf1));
        (, address ltLocker2,,,,,) = lp1.loans(address(vault),  address(ltlf2));
        (, address ltLocker3,,,,,) = lp1.loans(address(vault2), address(ltlf2));

        assertEq(IERC20(DAI).balanceOf(liqLocker),               25 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),  60 ether);  // Balance of Funding Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker2)), 15 ether);  // Balance of Funding Locker of vault 2
        assertEq(IERC20(vault).balanceOf(ltLocker),              45 ether);  // LoanToken balance of LT Locker
        assertEq(IERC20(vault).balanceOf(ltLocker2),             15 ether);  // LoanToken balance of LT Locker 2
        assertEq(IERC20(vault2).balanceOf(ltLocker3),            15 ether);  // LoanToken balance of LT Locker 3

        assertEq(IERC20(DAI).balanceOf(address(bob)), 90 ether);
        bob.withdraw(address(lp1));
        assertEq(IERC20(DAI).balanceOf(address(bob)), 100 ether); // Paid back initial share of 10% of pool
        // che.withdraw(address(lp1));                        // Can't withdraw because not enough funds are in liqLocker
        // dan.withdraw(address(lp1));
        assertTrue(false);
    }


}
