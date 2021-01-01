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
import "../LoanTokenLocker.sol";
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

    function claim(address lPool, address vault, address ltlf) external returns(uint[5] memory) {
        return ILiquidityPool(lPool).claim(vault, ltlf);  
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

    function makeFullPayment(address loanVault) external {
        LoanVault(loanVault).makeFullPayment();
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
    LiquidityPool                          lp2; 
    DSValue                          ethOracle;
    DSValue                          daiOracle;
    AmortizationRepaymentCalculator amortiCalc;
    BulletRepaymentCalculator       bulletCalc;
    LateFeeNullCalculator          lateFeeCalc;
    PremiumFlatCalculator          premiumCalc;
    IBPool                               bPool;
    PoolDelegate                           sid;
    PoolDelegate                           jon;
    LP                                     bob;
    LP                                     che;
    LP                                     dan;
    Borrower                               eli;
    Borrower                               fay;

    
    event DebugS(string, uint);

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
        sid            = new PoolDelegate();
        jon            = new PoolDelegate();
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

        globals.setPoolDelegateWhitelist(address(sid), true);
        globals.setPoolDelegateWhitelist(address(jon), true);
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), bPool.balanceOf(address(this)) / 2);
        bPool.transfer(address(jon), bPool.balanceOf(address(this)));

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
        lp1 = LiquidityPool(sid.createLiquidityPool(
            address(liqPoolFactory),
            DAI,
            address(bPool),
            500,
            100,
            "Maple Liquidity Pool 0",
            "MPL_LP_0"
        ));

        // Create Liquidity Pool
        lp2 = LiquidityPool(jon.createLiquidityPool(
            address(liqPoolFactory),
            DAI,
            address(bPool),
            7500,
            50,
            "Johns Liquidity Pool 480",
            "JRQ_LP_480"
        ));

        // vault Specifications
        uint256[6] memory specs_vault = [500, 180, 30, uint256(1000 ether), 2000, 7];
        bytes32[3] memory calcs_vault = [bytes32("BULLET"), bytes32("NULL"), bytes32("FLAT")];

        // vault2 Specifications
        uint256[6] memory specs_vault2 = [500, 180, 30, uint256(1000 ether), 2000, 7];
        bytes32[3] memory calcs_vault2 = [bytes32("AMORTIZATION"), bytes32("NULL"), bytes32("FLAT")];

        vault  = eli.createLoanVault(loanVFactory, DAI, WETH, specs_vault, calcs_vault);
        vault2 = fay.createLoanVault(loanVFactory, DAI, WETH, specs_vault2, calcs_vault2);
    }

    function test_stake_and_finalize() public {

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        address stakeLocker1 = lp1.stakeLockerAddress();
        address stakeLocker2 = lp2.stakeLockerAddress();
        sid.approve(address(bPool), stakeLocker1, uint(-1));
        jon.approve(address(bPool), stakeLocker2, uint(-1));

        // Pre-state checks.
        assertEq(bPool.balanceOf(address(sid)),                 50 * WAD);
        assertEq(bPool.balanceOf(address(jon)),                 50 * WAD);
        assertEq(bPool.balanceOf(stakeLocker1),                        0);
        assertEq(bPool.balanceOf(stakeLocker2),                        0);
        assertEq(IERC20(stakeLocker1).balanceOf(address(sid)),         0);
        assertEq(IERC20(stakeLocker2).balanceOf(address(jon)),         0);

        /**************************************/
        /*** Stake Respective Stake Lockers ***/
        /**************************************/
        sid.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(sid)) / 2);
        jon.stake(lp2.stakeLockerAddress(), bPool.balanceOf(address(jon)) / 2);

        // Post-state checks.
        assertEq(bPool.balanceOf(address(sid)),                25 * WAD);
        assertEq(bPool.balanceOf(address(jon)),                25 * WAD);
        assertEq(bPool.balanceOf(stakeLocker1),                25 * WAD);
        assertEq(bPool.balanceOf(stakeLocker2),                25 * WAD);
        assertEq(IERC20(stakeLocker1).balanceOf(address(sid)), 25 * WAD);
        assertEq(IERC20(stakeLocker2).balanceOf(address(jon)), 25 * WAD);

        /********************************/
        /*** Finalize Liquidity Pools ***/
        /********************************/
        lp1.finalize();
        lp2.finalize();

    }

    function test_deposit() public {
        address stakeLocker = lp1.stakeLockerAddress();
        address liqLocker   = lp1.liquidityLockerAddress();

        sid.approve(address(bPool), stakeLocker, uint(-1));
        sid.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(sid)) / 2);

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

    // function test_fundLoan() public {
    //     address stakeLocker   = lp1.stakeLockerAddress();
    //     address liqLocker     = lp1.liquidityLockerAddress();
    //     address fundingLocker = vault.fundingLocker();

    //     sid.approve(address(bPool), stakeLocker, uint(-1));
    //     sid.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(sid)) / 2);

    //     // Mint 100 DAI into this LP account
    //     mint("DAI", address(bob), 100 ether);

    //     lp1.finalize();

    //     bob.approve(DAI, address(lp1), uint(-1));

    //     assertTrue(bob.try_deposit(address(lp1), 100 ether));

    //     assertTrue(!sid.try_fundLoan(address(lp1), address(vault), address(ltlf1), 100 ether)); // LoanVaultFactory not in globals

    //     globals.setLoanVaultFactory(address(loanVFactory));

    //     assertEq(IERC20(DAI).balanceOf(liqLocker),               100 ether);  // Balance of Liquidity Locker
    //     assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),          0);  // Balance of Funding Locker
        
    //     /*******************/
    //     /*** Fund a Loan ***/
    //     /*******************/
    //     assertTrue(sid.try_fundLoan(address(lp1), address(vault), address(ltlf1), 20 ether));  // Fund loan for 20 DAI

    //     (
    //         address loanVaultFunded,
    //         address loanTokenLocker,
    //         uint256 amountFunded,
    //         uint256 principalPaid,
    //         uint256 interestPaid,
    //         uint256 feePaid,
    //         uint256 excessReturned
    //     ) = lp1.loans(address(vault), address(ltlf1));

    //     assertEq(ltlf1.lockers(0), loanTokenLocker);  // LTL instantiated

    //     assertEq(loanVaultFunded,  address(vault));
    //     assertEq(amountFunded,           20 ether); 
    //     assertEq(principalPaid,                 0);
    //     assertEq(interestPaid,                  0);
    //     assertEq(feePaid,                       0);
    //     assertEq(excessReturned,                0);

    //     assertEq(IERC20(DAI).balanceOf(liqLocker),              80 ether);  // Balance of Liquidity Locker
    //     assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 20 ether);  // Balance of Funding Locker
    //     assertEq(IERC20(vault).balanceOf(loanTokenLocker),      20 ether);  // LoanToken balance of LT Locker

    //     /****************************************/
    //     /*** Fund same loan with the same LTL ***/
    //     /****************************************/
    //     assertTrue(sid.try_fundLoan(address(lp1), address(vault), address(ltlf1), 25 ether)); // Fund loan for 25 DAI
    //     (
    //         loanVaultFunded,
    //         loanTokenLocker,
    //         amountFunded,
    //         principalPaid,
    //         interestPaid,
    //         feePaid,
    //         excessReturned
    //     ) = lp1.loans(address(vault), address(ltlf1));

    //     assertEq(ltlf1.lockers(0), loanTokenLocker);  // Same LTL

    //     assertEq(loanVaultFunded,  address(vault));
    //     assertEq(amountFunded,           45 ether); 
    //     assertEq(principalPaid,                 0);
    //     assertEq(interestPaid,                  0);
    //     assertEq(feePaid,                       0);
    //     assertEq(excessReturned,                0);

    //     assertEq(IERC20(DAI).balanceOf(liqLocker),              55 ether);  // Balance of Liquidity Locker
    //     assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 45 ether);  // Balance of Funding Locker
    //     assertEq(IERC20(vault).balanceOf(loanTokenLocker),      45 ether);  // LoanToken balance of LT Locker

    //     /*******************************************/
    //     /*** Fund same loan with a different LTL ***/
    //     /*******************************************/
    //     LoanTokenLockerFactory ltlf2 = new LoanTokenLockerFactory();
    //     assertTrue(sid.try_fundLoan(address(lp1), address(vault), address(ltlf2), 15 ether)); // Fund loan for 25 DAI

    //     (
    //         loanVaultFunded,
    //         loanTokenLocker,
    //         amountFunded,
    //         principalPaid,
    //         interestPaid,
    //         feePaid,
    //         excessReturned
    //     ) = lp1.loans(address(vault), address(ltlf2)); // Next struct in mapping, corrresponding to new LTL

    //     assertEq(ltlf2.lockers(0), loanTokenLocker);  // Same LTL

    //     assertEq(loanVaultFunded,  address(vault));
    //     assertEq(amountFunded,           15 ether); 
    //     assertEq(principalPaid,                 0);
    //     assertEq(interestPaid,                  0);
    //     assertEq(feePaid,                       0);
    //     assertEq(excessReturned,                0);

    //     assertEq(IERC20(DAI).balanceOf(liqLocker),              40 ether);  // Balance of Liquidity Locker
    //     assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 60 ether);  // Balance of Funding Locker
    //     assertEq(IERC20(vault).balanceOf(loanTokenLocker),      15 ether);  // LoanToken balance of LT Locker
    // }

    function test_claim_singleLP() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        address stakeLocker = lp1.stakeLockerAddress();
        address liqLocker   = lp1.liquidityLockerAddress();

        sid.approve(address(bPool), stakeLocker, uint(-1));
        sid.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(sid)) / 2);

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
        assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf1),   500 ether));
        assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf2),   500 ether));

        assertTrue(sid.try_fundLoan(address(lp1), address(vault2), address(ltlf1),   500 ether));
        assertTrue(sid.try_fundLoan(address(lp1), address(vault2), address(ltlf2),   500 ether));

        address ltl1 = lp1.loanTokenLockers(address(vault),  address(ltlf1));  // ltl1 = LoanTokenLocker 1, for vault using ltlf1
        address ltl2 = lp1.loanTokenLockers(address(vault),  address(ltlf2));  // ltl2 = LoanTokenLocker 2, for vault using ltlf2
        address ltl3 = lp1.loanTokenLockers(address(vault2), address(ltlf1));  // ltl3 = LoanTokenLocker 3, for vault2 using ltlf1
        address ltl4 = lp1.loanTokenLockers(address(vault2), address(ltlf2));  // ltl4 = LoanTokenLocker 4, for vault2 using ltlf2

        // Present state checks
        assertEq(IERC20(DAI).balanceOf(liqLocker),               8000 ether);  // 10000 DAI deposited - (1100 DAI + 1100 DAI)
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),  1000 ether);  // Balance of vault fl
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker2)), 1000 ether);  // Balance of vault2 fl
        assertEq(IERC20(vault).balanceOf(ltl1),                   500 ether);  // Balance of ltl1 for lp1 with ltlf1
        assertEq(IERC20(vault).balanceOf(ltl2),                   500 ether);  // Balance of ltl2 for lp1 with ltlf2
        assertEq(IERC20(vault2).balanceOf(ltl3),                  500 ether);  // Balance of ltl3 for lp1 with ltlf1
        assertEq(IERC20(vault2).balanceOf(ltl4),                  500 ether);  // Balance of ltl4 for lp1 with ltlf2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  vault.collateralRequiredForDrawdown(1000 ether); // wETH required for 1000 DAI drawdown on vault
            uint cReq2 = vault2.collateralRequiredForDrawdown(1000 ether); // wETH required for 1000 DAI drawdown on vault2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(vault),  cReq1);
            fay.approve(WETH, address(vault2), cReq2);
            eli.drawdown(address(vault),  1000 ether);
            fay.drawdown(address(vault2), 1000 ether);
        }
        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        {
            (uint amt1_1,,,) =  vault.getNextPayment(); // DAI required for 1st payment on vault
            (uint amt1_2,,,) = vault2.getNextPayment(); // DAI required for 1st payment on vault2
            mint("DAI", address(eli), amt1_1);
            mint("DAI", address(fay), amt1_2);
            eli.approve(DAI, address(vault),  amt1_1);
            fay.approve(DAI, address(vault2), amt1_2);
            eli.makePayment(address(vault));
            fay.makePayment(address(vault2));
        }
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        // TODO: Pre-state checks.
        // TODO: Post-state checks.

        // LiquidityPool claim() across ltl1, ltl2, ltl3, ltl4
        uint intPaid = vault.interestPaid();
        uint priPaid = vault.principalPaid();
        uint feePaid = vault.feePaid();
        uint excPaid = vault.excessReturned();
        uint intPaid2 = vault2.interestPaid();
        uint priPaid2 = vault2.principalPaid();
        uint feePaid2 = vault2.feePaid();
        uint excPaid2 = vault2.excessReturned();

        // // Snapshot theory, the original holder of tokens claims the tokens.
        // // When updateFundsReceived() is fired, the contract holding the ERC-2222 tokens
        // // is the only contract then allowed to claim associated fundsDistributed().
        
        // // To test this, we do normal claim as follows ...
        // LoanTokenLocker LTL_1 = LoanTokenLocker(ltl1);
        // LTL_1.claim();

        // // ... with follow up claim by LP.
        // // ... note this leaves funds locked in LoanTokenLocker, but they are claimed as expected.
        // uint[5] memory claim1 = sid.claim(address(lp1), address(vault),   address(ltlf1));

        // // Now we reverse order of claim and attempt to make claim from LiquidityPool ...
        // // ... even though LoanTokens were held in LoanTokenLocker at time of updateFundsReceived() call.
        // // The following will fail / allow the LiquidityPool to claim nothing.
        // uint[5] memory claim2 = sid.claim(address(lp1), address(vault),   address(ltlf2));
        // LoanTokenLocker LTL_2 = LoanTokenLocker(ltl2);

        // // Lo and behold, we are able to claim everything via LoanTokenLocker after failed LP claim() attempt.
        // LTL_2.claim();

        {
            // New implementation:
            uint[5] memory claim1 = sid.claim(address(lp1), address(vault),   address(ltlf1));
            uint[5] memory claim2 = sid.claim(address(lp1), address(vault),   address(ltlf2));

            uint[5] memory claim3 = sid.claim(address(lp1), address(vault2),  address(ltlf1));
            uint[5] memory claim4 = sid.claim(address(lp1), address(vault2),  address(ltlf2));

            assertEq(claim1[0], 10);
            assertEq(claim1[1], 11);
            assertEq(claim1[2], 12);
            assertEq(claim1[3], 13);
            assertEq(claim1[4], 14);

            assertEq(claim2[0], 20);
            assertEq(claim2[1], 21);
            assertEq(claim2[2], 22);
            assertEq(claim2[3], 23);
            assertEq(claim2[4], 24);
            
            assertEq(claim3[0], 30);
            assertEq(claim3[1], 31);
            assertEq(claim3[2], 32);
            assertEq(claim3[3], 33);
            assertEq(claim3[4], 34);
            
            assertEq(claim4[0], 40);
            assertEq(claim4[1], 41);
            assertEq(claim4[2], 42);
            assertEq(claim4[3], 43);
            assertEq(claim4[4], 44);
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        // TODO: Pre-state checks.
        // TODO: Post-state checks.

        {
            (uint amt2_1,,,) =  vault.getNextPayment(); // DAI required for 2nd payment on vault
            (uint amt2_2,,,) = vault2.getNextPayment(); // DAI required for 2nd payment on vault2
            mint("DAI", address(eli), amt2_1);
            mint("DAI", address(fay), amt2_2);
            eli.approve(DAI, address(vault),  amt2_1);
            fay.approve(DAI, address(vault2), amt2_2);
            eli.makePayment(address(vault));
            fay.makePayment(address(vault2));

            (uint amt3_1,,,) =  vault.getNextPayment(); // DAI required for 3rd payment on vault
            (uint amt3_2,,,) = vault2.getNextPayment(); // DAI required for 3rd payment on vault2
            mint("DAI", address(eli), amt3_1);
            mint("DAI", address(fay), amt3_2);
            eli.approve(DAI, address(vault),  amt3_1);
            fay.approve(DAI, address(vault2), amt3_2);
            eli.makePayment(address(vault));
            fay.makePayment(address(vault2));
        }
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        // TODO: Pre-state checks.
        // TODO: Post-state checks.

        {
            uint[5] memory claim5 = sid.claim(address(lp1), address(vault),   address(ltlf1));
            uint[5] memory claim6 = sid.claim(address(lp1), address(vault),   address(ltlf2));
            uint[5] memory claim7 = sid.claim(address(lp1), address(vault2),  address(ltlf1));
            uint[5] memory claim8 = sid.claim(address(lp1), address(vault2),  address(ltlf2));

            assertEq(claim5[0], 50);
            assertEq(claim5[1], 51);
            assertEq(claim5[2], 52);
            assertEq(claim5[3], 53);
            assertEq(claim5[4], 54);

            assertEq(claim6[0], 60);
            assertEq(claim6[1], 61);
            assertEq(claim6[2], 62);
            assertEq(claim6[3], 63);
            assertEq(claim6[4], 64);
            
            assertEq(claim7[0], 70);
            assertEq(claim7[1], 71);
            assertEq(claim7[2], 72);
            assertEq(claim7[3], 73);
            assertEq(claim7[4], 74);
            
            assertEq(claim8[0], 80);
            assertEq(claim8[1], 81);
            assertEq(claim8[2], 82);
            assertEq(claim8[3], 83);
            assertEq(claim8[4], 84);
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        // TODO: Pre-state checks.
        // TODO: Post-state checks.

        {
            (uint amtf_1,,) =  vault.getFullPayment(); // DAI required for 2nd payment on vault
            (uint amtf_2,,) = vault2.getFullPayment(); // DAI required for 2nd payment on vault2
            mint("DAI", address(eli), amtf_1);
            mint("DAI", address(fay), amtf_2);
            eli.approve(DAI, address(vault),  amtf_1);
            fay.approve(DAI, address(vault2), amtf_2);
            eli.makeFullPayment(address(vault));
            fay.makeFullPayment(address(vault2));
        }
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        // TODO: Pre-state checks.
        // TODO: Post-state checks.

        {
            uint[5] memory claim9  = sid.claim(address(lp1), address(vault),   address(ltlf1));
            uint[5] memory claim10 = sid.claim(address(lp1), address(vault),   address(ltlf2));
            uint[5] memory claim11 = sid.claim(address(lp1), address(vault2),  address(ltlf1));
            uint[5] memory claim12 = sid.claim(address(lp1), address(vault2),  address(ltlf2));

            assertEq(claim9[0], 90);
            assertEq(claim9[1], 91);
            assertEq(claim9[2], 92);
            assertEq(claim9[3], 93);
            assertEq(claim9[4], 94);

            assertEq(claim10[0], 100);
            assertEq(claim10[1], 101);
            assertEq(claim10[2], 102);
            assertEq(claim10[3], 103);
            assertEq(claim10[4], 104);
            
            assertEq(claim11[0], 110);
            assertEq(claim11[1], 111);
            assertEq(claim11[2], 112);
            assertEq(claim11[3], 113);
            assertEq(claim11[4], 114);
            
            assertEq(claim12[0], 120);
            assertEq(claim12[1], 121);
            assertEq(claim12[2], 122);
            assertEq(claim12[3], 123);
            assertEq(claim12[4], 124);

            // Ensure both loans are matured.
            assertEq(uint256(vault.loanState()),  2);
            assertEq(uint256(vault2.loanState()), 2);
        }

    }

    function test_claim_multipleLP() public {

        /******************************************/
        /*** Stake & Finalize 2 Liquidity Pools ***/
        /******************************************/
        address stakeLocker1 = lp1.stakeLockerAddress();
        address stakeLocker2 = lp2.stakeLockerAddress();
        sid.approve(address(bPool), stakeLocker1, uint(-1));
        jon.approve(address(bPool), stakeLocker2, uint(-1));
        sid.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(sid)) / 2);
        jon.stake(lp2.stakeLockerAddress(), bPool.balanceOf(address(jon)) / 2);
        lp1.finalize();
        lp2.finalize();

        address liqLocker1 = lp1.liquidityLockerAddress();
        address liqLocker2 = lp2.liquidityLockerAddress();

        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        mint("DAI", address(bob), 10000 ether);
        mint("DAI", address(che), 10000 ether);
        mint("DAI", address(dan), 10000 ether);

        bob.approve(DAI, address(lp1), uint(-1));
        che.approve(DAI, address(lp1), uint(-1));
        dan.approve(DAI, address(lp1), uint(-1));

        bob.approve(DAI, address(lp2), uint(-1));
        che.approve(DAI, address(lp2), uint(-1));
        dan.approve(DAI, address(lp2), uint(-1));

        assertTrue(bob.try_deposit(address(lp1), 1000 ether));  // 10% BOB in LP1
        assertTrue(che.try_deposit(address(lp1), 3000 ether));  // 30% CHE in LP1
        assertTrue(dan.try_deposit(address(lp1), 6000 ether));  // 60% DAN in LP1

        assertTrue(bob.try_deposit(address(lp2), 4000 ether));  // 40% BOB in LP2
        assertTrue(che.try_deposit(address(lp2), 3000 ether));  // 30% BOB in LP2
        assertTrue(dan.try_deposit(address(lp2), 3000 ether));  // 30% BOB in LP2

        globals.setLoanVaultFactory(address(loanVFactory)); // Don't remove, not done in setUp()

        address fundingLocker  = vault.fundingLocker();
        address fundingLocker2 = vault2.fundingLocker();

        /***************************/
        /*** Fund vault / vault2 ***/
        /***************************/
        assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf1), 250 ether));  // Fund vault using ltlf1 for 250 DAI
        assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf1), 250 ether));  // Fund vault using ltlf1 for 250 DAI, again, 500 DAI total
        assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf2), 250 ether));  // Fund vault using ltlf2 for 250 DAI
        assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf2), 250 ether));  // Fund vault using ltlf2 for 250 DAI (no excess), 1000 DAI total

        assertTrue(jon.try_fundLoan(address(lp2), address(vault),  address(ltlf1), 500 ether));  // Fund vault using ltlf1 for 500 DAI (excess), 1500 DAI total
        assertTrue(jon.try_fundLoan(address(lp2), address(vault),  address(ltlf2), 500 ether));  // Fund vault using ltlf2 for 500 DAI (excess), 2000 DAI total

        assertTrue(sid.try_fundLoan(address(lp1), address(vault2),  address(ltlf1), 100 ether));  // Fund vault using ltlf1 for 100 DAI
        assertTrue(sid.try_fundLoan(address(lp1), address(vault2),  address(ltlf1), 100 ether));  // Fund vault using ltlf1 for 100 DAI, again, 200 DAI total
        assertTrue(sid.try_fundLoan(address(lp1), address(vault2),  address(ltlf2), 100 ether));  // Fund vault using ltlf2 for 100 DAI
        assertTrue(sid.try_fundLoan(address(lp1), address(vault2),  address(ltlf2), 100 ether));  // Fund vault using ltlf2 for 100 DAI again, 400 DAI total

        assertTrue(jon.try_fundLoan(address(lp2), address(vault2),  address(ltlf1), 150 ether));  // Fund vault using ltlf1 for 150 DAI
        assertTrue(jon.try_fundLoan(address(lp2), address(vault2),  address(ltlf1), 150 ether));  // Fund vault using ltlf1 for 150 DAI, again, 700 DAI total
        assertTrue(jon.try_fundLoan(address(lp2), address(vault2),  address(ltlf2), 150 ether));  // Fund vault using ltlf2 for 150 DAI
        assertTrue(jon.try_fundLoan(address(lp2), address(vault2),  address(ltlf2), 150 ether));  // Fund vault using ltlf2 for 150 DAI (no excess), 1000 DAI total

        address ltl1_lp1 = lp1.loanTokenLockers(address(vault),  address(ltlf1));  // ltl1_lp1 = LoanTokenLocker 1, for lp1, for vault using ltlf1
        address ltl2_lp1 = lp1.loanTokenLockers(address(vault),  address(ltlf2));  // ltl2_lp1 = LoanTokenLocker 2, for lp1, for vault using ltlf2
        address ltl3_lp1 = lp1.loanTokenLockers(address(vault2), address(ltlf1));  // ltl3_lp1 = LoanTokenLocker 3, for lp1, for vault2 using ltlf1
        address ltl4_lp1 = lp1.loanTokenLockers(address(vault2), address(ltlf2));  // ltl4_lp1 = LoanTokenLocker 4, for lp1, for vault2 using ltlf2
        address ltl1_lp2 = lp2.loanTokenLockers(address(vault),  address(ltlf1));  // ltl1_lp2 = LoanTokenLocker 1, for lp2, for vault using ltlf1
        address ltl2_lp2 = lp2.loanTokenLockers(address(vault),  address(ltlf2));  // ltl2_lp2 = LoanTokenLocker 2, for lp2, for vault using ltlf2
        address ltl3_lp2 = lp2.loanTokenLockers(address(vault2), address(ltlf1));  // ltl3_lp2 = LoanTokenLocker 3, for lp2, for vault2 using ltlf1
        address ltl4_lp2 = lp2.loanTokenLockers(address(vault2), address(ltlf2));  // ltl4_lp2 = LoanTokenLocker 4, for lp2, for vault2 using ltlf2

        // Present state checks
        assertEq(IERC20(DAI).balanceOf(liqLocker1),              8600 ether);  // 10000 DAI deposited - (1000 DAI + 400 DAI)
        assertEq(IERC20(DAI).balanceOf(liqLocker2),              8400 ether);  // 10000 DAI deposited - (1000 DAI + 600 DAI)
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),  2000 ether);  // Balance of vault fl (excess, 1000 DAI from LP1 & 1000 DAI from LP2)
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker2)), 1000 ether);  // Balance of vault2 fl (no excess, exactly 400 DAI from LP1 & 600 DAI from LP2)
        assertEq(IERC20(vault).balanceOf(ltl1_lp1),               500 ether);  // Balance of ltl1 for lp1 with ltlf1
        assertEq(IERC20(vault).balanceOf(ltl2_lp1),               500 ether);  // Balance of ltl2 for lp1 with ltlf2
        assertEq(IERC20(vault2).balanceOf(ltl3_lp1),              200 ether);  // Balance of ltl3 for lp1 with ltlf1
        assertEq(IERC20(vault2).balanceOf(ltl4_lp1),              200 ether);  // Balance of ltl4 for lp1 with ltlf2
        assertEq(IERC20(vault).balanceOf(ltl1_lp2),               500 ether);  // Balance of ltl1 for lp2 with ltlf1
        assertEq(IERC20(vault).balanceOf(ltl2_lp2),               500 ether);  // Balance of ltl2 for lp2 with ltlf2
        assertEq(IERC20(vault2).balanceOf(ltl3_lp2),              300 ether);  // Balance of ltl3 for lp2 with ltlf1
        assertEq(IERC20(vault2).balanceOf(ltl4_lp2),              300 ether);  // Balance of ltl4 for lp2 with ltlf2

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
        // TODO: Pre-state checks.
        // TODO: Post-state checks.

        // LiquidityPool claim() across ltl1, ltl2, ltl3, ltl4
        uint intPaid = vault.interestPaid();
        uint priPaid = vault.principalPaid();
        uint feePaid = vault.feePaid();
        uint excPaid = vault.excessReturned();

        uint[5] memory claim1_lp1 = sid.claim(address(lp1), address(vault),   address(ltlf1));
        uint[5] memory claim2_lp1 = sid.claim(address(lp1), address(vault),   address(ltlf2));
        uint[5] memory claim3_lp1 = sid.claim(address(lp1), address(vault2),  address(ltlf1));
        uint[5] memory claim4_lp1 = sid.claim(address(lp1), address(vault2),  address(ltlf2));

        uint[5] memory claim1_lp2 = sid.claim(address(lp2), address(vault),   address(ltlf1)); // Note who is calling this.
        uint[5] memory claim2_lp2 = sid.claim(address(lp2), address(vault),   address(ltlf2)); // It's Sid, who is a pool delegate elsewhere.
        uint[5] memory claim3_lp2 = sid.claim(address(lp2), address(vault2),  address(ltlf1)); // This is expected behavior.
        uint[5] memory claim4_lp2 = sid.claim(address(lp2), address(vault2),  address(ltlf2)); // Claim is public, to enable free flowing fund claims.

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        // TODO: Pre-state checks.
        // TODO: Post-state checks.

        (uint amt2_1,,,) =  vault.getNextPayment(); // DAI required for 2nd payment on vault
        (uint amt2_2,,,) = vault2.getNextPayment(); // DAI required for 2nd payment on vault2
        mint("DAI", address(eli), amt2_1);
        mint("DAI", address(fay), amt2_2);
        eli.approve(DAI, address(vault),  amt2_1);
        fay.approve(DAI, address(vault2), amt2_2);
        eli.makePayment(address(vault));
        fay.makePayment(address(vault2));

        (uint amt3_1,,,) =  vault.getNextPayment(); // DAI required for 3rd payment on vault
        (uint amt3_2,,,) = vault2.getNextPayment(); // DAI required for 3rd payment on vault2
        mint("DAI", address(eli), amt3_1);
        mint("DAI", address(fay), amt3_2);
        eli.approve(DAI, address(vault),  amt3_1);
        fay.approve(DAI, address(vault2), amt3_2);
        eli.makePayment(address(vault));
        fay.makePayment(address(vault2));
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        // TODO: Pre-state checks.
        // TODO: Post-state checks.

        uint[5] memory claim5_lp1 = sid.claim(address(lp1), address(vault),   address(ltlf1));
        uint[5] memory claim6_lp1 = sid.claim(address(lp1), address(vault),   address(ltlf2));
        uint[5] memory claim7_lp1 = sid.claim(address(lp1), address(vault2),  address(ltlf1));
        uint[5] memory claim8_lp1 = sid.claim(address(lp1), address(vault2),  address(ltlf2));

        uint[5] memory claim5_lp2 = sid.claim(address(lp2), address(vault),   address(ltlf1));
        uint[5] memory claim6_lp2 = sid.claim(address(lp2), address(vault),   address(ltlf2));
        uint[5] memory claim7_lp2 = sid.claim(address(lp2), address(vault2),  address(ltlf1));
        uint[5] memory claim8_lp2 = sid.claim(address(lp2), address(vault2),  address(ltlf2));
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        // TODO: Pre-state checks.
        // TODO: Post-state checks.

        (uint amtf_1,,) =  vault.getFullPayment(); // DAI required for 2nd payment on vault
        (uint amtf_2,,) = vault2.getFullPayment(); // DAI required for 2nd payment on vault2
        mint("DAI", address(eli), amtf_1);
        mint("DAI", address(fay), amtf_2);
        eli.approve(DAI, address(vault),  amtf_1);
        fay.approve(DAI, address(vault2), amtf_2);
        eli.makeFullPayment(address(vault));
        fay.makeFullPayment(address(vault2));
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        // TODO: Pre-state checks.
        // TODO: Post-state checks.

        uint[5] memory claim9_lp1  = sid.claim(address(lp1), address(vault),   address(ltlf1));
        uint[5] memory claim10_lp1 = sid.claim(address(lp1), address(vault),   address(ltlf2));
        uint[5] memory claim11_lp1 = sid.claim(address(lp1), address(vault2),  address(ltlf1));
        uint[5] memory claim12_lp1 = sid.claim(address(lp1), address(vault2),  address(ltlf2));

        uint[5] memory claim9_lp2  = sid.claim(address(lp2), address(vault),   address(ltlf1));
        uint[5] memory claim10_lp2 = sid.claim(address(lp2), address(vault),   address(ltlf2));
        uint[5] memory claim11_lp2 = sid.claim(address(lp2), address(vault2),  address(ltlf1));
        uint[5] memory claim12_lp2 = sid.claim(address(lp2), address(vault2),  address(ltlf2));

        // Ensure both loans are matured.
        assertEq(uint256(vault.loanState()),  2);
        assertEq(uint256(vault2.loanState()), 2);

    }

    function test_withdraw() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        address stakeLocker = lp1.stakeLockerAddress();
        address liqLocker   = lp1.liquidityLockerAddress();

        sid.approve(address(bPool), stakeLocker, uint(-1));
        sid.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(sid)) / 2);

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

        assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf1),  20 ether));  // Fund loan for 20 DAI
        assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf1),  25 ether));  // Fund same loan for 25 DAI
        assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf2), 15 ether));  // Fund new loan same vault for 15 DAI
        assertTrue(sid.try_fundLoan(address(lp1), address(vault2), address(ltlf2), 15 ether));  // Fund new loan new vault for 15 DAI

        address ltLocker  = lp1.loanTokenLockers(address(vault),  address(ltlf1));
        address ltLocker2 = lp1.loanTokenLockers(address(vault),  address(ltlf2));
        address ltLocker3 = lp1.loanTokenLockers(address(vault2), address(ltlf2));

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
