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
}

contract Borrower {

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
    PoolDelegate                           joe;
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
        joe            = new PoolDelegate();
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
        globals.setPoolDelegateWhitelist(address(joe), true);
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), bPool.balanceOf(address(this)) / 2);
        bPool.transfer(address(joe), bPool.balanceOf(address(this)));

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
        lp2 = LiquidityPool(joe.createLiquidityPool(
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
        joe.approve(address(bPool), stakeLocker2, uint(-1));

        // Pre-state checks.
        assertEq(bPool.balanceOf(address(sid)),                 50 * WAD);
        assertEq(bPool.balanceOf(address(joe)),                 50 * WAD);
        assertEq(bPool.balanceOf(stakeLocker1),                        0);
        assertEq(bPool.balanceOf(stakeLocker2),                        0);
        assertEq(IERC20(stakeLocker1).balanceOf(address(sid)),         0);
        assertEq(IERC20(stakeLocker2).balanceOf(address(joe)),         0);

        /**************************************/
        /*** Stake Respective Stake Lockers ***/
        /**************************************/
        sid.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(sid)) / 2);
        joe.stake(lp2.stakeLockerAddress(), bPool.balanceOf(address(joe)) / 2);

        // Post-state checks.
        assertEq(bPool.balanceOf(address(sid)),                25 * WAD);
        assertEq(bPool.balanceOf(address(joe)),                25 * WAD);
        assertEq(bPool.balanceOf(stakeLocker1),                25 * WAD);
        assertEq(bPool.balanceOf(stakeLocker2),                25 * WAD);
        assertEq(IERC20(stakeLocker1).balanceOf(address(sid)), 25 * WAD);
        assertEq(IERC20(stakeLocker2).balanceOf(address(joe)), 25 * WAD);

        /********************************/
        /*** Finalize Liquidity Pools ***/
        /********************************/
        lp1.finalize();
        lp2.finalize();

        // TODO: Post-state assertions to finalize().

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

    function test_fundLoan() public {
        address stakeLocker   = lp1.stakeLockerAddress();
        address liqLocker     = lp1.liquidityLockerAddress();
        address fundingLocker = vault.fundingLocker();

        sid.approve(address(bPool), stakeLocker, uint(-1));
        sid.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(sid)) / 2);

        // Mint 100 DAI into this LP account
        mint("DAI", address(bob), 100 ether);

        lp1.finalize();

        bob.approve(DAI, address(lp1), uint(-1));

        assertTrue(bob.try_deposit(address(lp1), 100 ether));

        assertTrue(!sid.try_fundLoan(address(lp1), address(vault), address(ltlf1), 100 ether)); // LoanVaultFactory not in globals

        globals.setLoanVaultFactory(address(loanVFactory));

        assertEq(IERC20(DAI).balanceOf(liqLocker),               100 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),          0);  // Balance of Funding Locker
        
        /*******************/
        /*** Fund a Loan ***/
        /*******************/
        assertTrue(sid.try_fundLoan(address(lp1), address(vault), address(ltlf1), 20 ether));  // Fund loan for 20 DAI

        LoanTokenLocker ltl = LoanTokenLocker(lp1.loanTokenLockers(address(vault),  address(ltlf1)));

        assertEq(ltl.vault(), address(vault));
        assertEq(ltl.owner(), address(lp1));
        assertEq(ltl.asset(), DAI);

        assertEq(ltlf1.lockers(0), address(ltl));  // LTL instantiated

        assertEq(IERC20(DAI).balanceOf(liqLocker),              80 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 20 ether);  // Balance of Funding Locker
        assertEq(IERC20(vault).balanceOf(address(ltl)),         20 ether);  // LoanToken balance of LT Locker
        assertEq(lp1.principalSum(),                            20 ether);  // Outstanding principal in liqiudity pool 1

        /****************************************/
        /*** Fund same loan with the same LTL ***/
        /****************************************/
        assertTrue(sid.try_fundLoan(address(lp1), address(vault), address(ltlf1), 25 ether)); // Fund same loan for 25 DAI

        assertEq(ltlf1.lockers(0), address(ltl));  // Same LTL

        assertEq(IERC20(DAI).balanceOf(liqLocker),              55 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 45 ether);  // Balance of Funding Locker
        assertEq(IERC20(vault).balanceOf(address(ltl)),         45 ether);  // LoanToken balance of LT Locker
        assertEq(lp1.principalSum(),                            45 ether);  // Outstanding principal in liqiudity pool 1

        /*******************************************/
        /*** Fund same loan with a different LTL ***/
        /*******************************************/
        LoanTokenLockerFactory ltlf2 = new LoanTokenLockerFactory();
        assertTrue(sid.try_fundLoan(address(lp1), address(vault), address(ltlf2), 10 ether)); // Fund loan for 15 DAI

        LoanTokenLocker ltl2 = LoanTokenLocker(lp1.loanTokenLockers(address(vault),  address(ltlf2)));

        assertEq(ltl2.vault(), address(vault));
        assertEq(ltl2.owner(), address(lp1));
        assertEq(ltl2.asset(), DAI);

        assertEq(ltlf2.lockers(0), address(ltl2));  // LTL instantiated

        assertEq(IERC20(DAI).balanceOf(liqLocker),              45 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 55 ether);  // Balance of Funding Locker
        assertEq(IERC20(vault).balanceOf(address(ltl2)),        10 ether);  // LoanToken balance of LT Locker 2
        assertEq(lp1.principalSum(),                            55 ether);  // Outstanding principal in liqiudity pool 1
    }

    function checkClaim(LoanTokenLocker ltl, LoanVault vault, PoolDelegate pd, IERC20 reqAsset, LiquidityPool lp, address ltlf) internal {
        uint256[10] memory balances = [
            reqAsset.balanceOf(address(ltl)),
            reqAsset.balanceOf(address(lp)),
            reqAsset.balanceOf(address(pd)),
            reqAsset.balanceOf(lp.stakeLockerAddress()),
            reqAsset.balanceOf(lp.liquidityLockerAddress()),
            0,0,0,0,0
        ];

        uint256[4] memory vaultData = [
            vault.interestPaid(),
            vault.principalPaid(),
            vault.feePaid(),
            vault.excessReturned()
        ];

        uint256[8] memory ltlData = [
            ltl.interestPaid(),
            ltl.principalPaid(),
            ltl.feePaid(),
            ltl.excessReturned(),
            0,0,0,0
        ];

        uint[5] memory claim = pd.claim(address(lp), address(vault),   address(ltlf));

        // Updated LTL state variables
        ltlData[4] = ltl.interestPaid();
        ltlData[5] = ltl.principalPaid();
        ltlData[6] = ltl.feePaid();
        ltlData[7] = ltl.excessReturned();

        balances[5] = reqAsset.balanceOf(address(ltl));
        balances[6] = reqAsset.balanceOf(address(lp));
        balances[7] = reqAsset.balanceOf(address(pd));
        balances[8] = reqAsset.balanceOf(lp.stakeLockerAddress());
        balances[9] = reqAsset.balanceOf(lp.liquidityLockerAddress());

        uint256 sumTransfer;
        uint256 sumNetNew;

        for(uint i = 0; i < 4; i++) sumNetNew += (vaultData[i] - ltlData[i]);

        {
            for(uint i = 0; i < 4; i++) {
                assertEq(ltlData[i + 4], vaultData[i]);  // LTL updated to reflect vault state

                // Category portion of claim * LTL asset balance 
                // Eg. (interestClaimed / totalClaimed) * balance = Portion of total claim balance that is interest
                uint256 vaultShare = (vaultData[i] - ltlData[i]) * 1 ether / sumNetNew * claim[0] / 1 ether;
                assertEq(vaultShare, claim[i + 1]);

                sumTransfer += balances[i + 6] - balances[i + 1]; // Sum up all transfers that occured from claim
            }
            assertEq(claim[0], sumTransfer); // Assert balance from withdrawFunds equals sum of transfers
        }

        {
            assertEq(balances[5] - balances[0], 0);  // LTL locker should have transferred ALL funds claimed to LP
            assertEq(balances[6] - balances[1], 0);  // LP         should have transferred ALL funds claimed to LL, SL, and PD

            assertEq(balances[7] - balances[2], claim[3] + claim[1] * lp.delegateFee() / 10_000);  // Pool delegate claim (feePaid + delegateFee portion of interest)
            assertEq(balances[8] - balances[3],            claim[1] * lp.stakingFee()  / 10_000);  // Staking Locker claim (feePaid + stakingFee portion of interest)

            // Liquidity Locker (principal + excess + remaining portion of interest) (remaining balance from claim)
            // liqLockerClaimed = totalClaimed - pdClaimed - sLockerClaimed
            assertEq(balances[9] - balances[4], claim[0] - (balances[7] - balances[2]) - (balances[8] - balances[3]));
        }
    }

    function test_claim_singleLP() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            sid.approve(address(bPool), lp1.stakeLockerAddress(), uint(-1));
            sid.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(sid)) / 2);

            lp1.finalize();
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("DAI", address(bob), 1_000_000_000 ether);
            mint("DAI", address(che), 1_000_000_000 ether);
            mint("DAI", address(dan), 1_000_000_000 ether);

            bob.approve(DAI, address(lp1), uint(-1));
            che.approve(DAI, address(lp1), uint(-1));
            dan.approve(DAI, address(lp1), uint(-1));

            assertTrue(bob.try_deposit(address(lp1), 100_000_000 ether));  // 10%
            assertTrue(che.try_deposit(address(lp1), 300_000_000 ether));  // 30%
            assertTrue(dan.try_deposit(address(lp1), 600_000_000 ether));  // 60%

            globals.setLoanVaultFactory(address(loanVFactory)); // Don't remove, not done in setUp()
        }

        address fundingLocker  = vault.fundingLocker();
        address fundingLocker2 = vault2.fundingLocker();

        /************************************/
        /*** Fund vault / vault2 (Excess) ***/
        /************************************/
        {
            assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf1), 100_000_000 ether));
            assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf1), 100_000_000 ether));
            assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf2), 200_000_000 ether));
            assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf2), 200_000_000 ether));

            assertTrue(sid.try_fundLoan(address(lp1), address(vault2), address(ltlf1),  50_000_000 ether));
            assertTrue(sid.try_fundLoan(address(lp1), address(vault2), address(ltlf1),  50_000_000 ether));
            assertTrue(sid.try_fundLoan(address(lp1), address(vault2), address(ltlf2), 150_000_000 ether));
            assertTrue(sid.try_fundLoan(address(lp1), address(vault2), address(ltlf2), 150_000_000 ether));
        }

        LoanTokenLocker ltl1 = LoanTokenLocker(lp1.loanTokenLockers(address(vault),  address(ltlf1)));  // ltl1 = LoanTokenLocker 1, for vault using ltlf1
        LoanTokenLocker ltl2 = LoanTokenLocker(lp1.loanTokenLockers(address(vault),  address(ltlf2)));  // ltl2 = LoanTokenLocker 2, for vault using ltlf2
        LoanTokenLocker ltl3 = LoanTokenLocker(lp1.loanTokenLockers(address(vault2), address(ltlf1)));  // ltl3 = LoanTokenLocker 3, for vault2 using ltlf1
        LoanTokenLocker ltl4 = LoanTokenLocker(lp1.loanTokenLockers(address(vault2), address(ltlf2)));  // ltl4 = LoanTokenLocker 4, for vault2 using ltlf2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  vault.collateralRequiredForDrawdown(100_000_000 ether); // wETH required for 100_000_000 DAI drawdown on vault
            uint cReq2 = vault2.collateralRequiredForDrawdown(100_000_000 ether); // wETH required for 100_000_000 DAI drawdown on vault2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(vault),  cReq1);
            fay.approve(WETH, address(vault2), cReq2);
            eli.drawdown(address(vault),  100_000_000 ether);
            fay.drawdown(address(vault2), 100_000_000 ether);
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
        
        /****************/
        /*** LP Claim ***/
        /****************/
        {      
            checkClaim(ltl1, vault,  sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl2, vault,  sid, IERC20(DAI), lp1, address(ltlf2));
            checkClaim(ltl3, vault2, sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl4, vault2, sid, IERC20(DAI), lp1, address(ltlf2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
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
        
        /****************/
        /*** LP Claim ***/
        /****************/
        {      
            checkClaim(ltl1, vault,  sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl2, vault,  sid, IERC20(DAI), lp1, address(ltlf2));
            checkClaim(ltl3, vault2, sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl4, vault2, sid, IERC20(DAI), lp1, address(ltlf2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
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
        
        /****************/
        /*** LP Claim ***/
        /****************/
        {      
            checkClaim(ltl1, vault,  sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl2, vault,  sid, IERC20(DAI), lp1, address(ltlf2));
            checkClaim(ltl3, vault2, sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl4, vault2, sid, IERC20(DAI), lp1, address(ltlf2));

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
        {
            sid.approve(address(bPool), stakeLocker1, uint(-1));
            joe.approve(address(bPool), stakeLocker2, uint(-1));
            sid.stake(lp1.stakeLockerAddress(), bPool.balanceOf(address(sid)) / 2);
            joe.stake(lp2.stakeLockerAddress(), bPool.balanceOf(address(joe)) / 2);
            lp1.finalize();
            lp2.finalize();
        }
       
        address liqLocker1 = lp1.liquidityLockerAddress();
        address liqLocker2 = lp2.liquidityLockerAddress();

        /*************************************************************/
        /*** Mint and deposit funds into liquidity pools (1b each) ***/
        /*************************************************************/
        {
            mint("DAI", address(bob), 1_000_000_000 ether);
            mint("DAI", address(che), 1_000_000_000 ether);
            mint("DAI", address(dan), 1_000_000_000 ether);

            bob.approve(DAI, address(lp1), uint(-1));
            che.approve(DAI, address(lp1), uint(-1));
            dan.approve(DAI, address(lp1), uint(-1));

            bob.approve(DAI, address(lp2), uint(-1));
            che.approve(DAI, address(lp2), uint(-1));
            dan.approve(DAI, address(lp2), uint(-1));

            assertTrue(bob.try_deposit(address(lp1), 100_000_000 ether));  // 10% BOB in LP1
            assertTrue(che.try_deposit(address(lp1), 300_000_000 ether));  // 30% CHE in LP1
            assertTrue(dan.try_deposit(address(lp1), 600_000_000 ether));  // 60% DAN in LP1

            assertTrue(bob.try_deposit(address(lp2), 500_000_000 ether));  // 50% BOB in LP2
            assertTrue(che.try_deposit(address(lp2), 400_000_000 ether));  // 40% BOB in LP2
            assertTrue(dan.try_deposit(address(lp2), 100_000_000 ether));  // 10% BOB in LP2

            globals.setLoanVaultFactory(address(loanVFactory)); // Don't remove, not done in setUp()
        }
        
        address fundingLocker  = vault.fundingLocker();
        address fundingLocker2 = vault2.fundingLocker();

        /***************************/
        /*** Fund vault / vault2 ***/
        /***************************/
        {
            // LP 1 Vault 1
            assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf1), 25_000_000 ether));  // Fund vault using ltlf1 for 25m DAI
            assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf1), 25_000_000 ether));  // Fund vault using ltlf1 for 25m DAI, again, 50m DAI total
            assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf2), 25_000_000 ether));  // Fund vault using ltlf2 for 25m DAI
            assertTrue(sid.try_fundLoan(address(lp1), address(vault),  address(ltlf2), 25_000_000 ether));  // Fund vault using ltlf2 for 25m DAI (no excess), 100m DAI total

            // LP 2 Vault 1
            assertTrue(joe.try_fundLoan(address(lp2), address(vault),  address(ltlf1), 50_000_000 ether));  // Fund vault using ltlf1 for 50m DAI (excess), 150m DAI total
            assertTrue(joe.try_fundLoan(address(lp2), address(vault),  address(ltlf2), 50_000_000 ether));  // Fund vault using ltlf2 for 50m DAI (excess), 200m DAI total

            // LP 1 Vault 2
            assertTrue(sid.try_fundLoan(address(lp1), address(vault2),  address(ltlf1), 50_000_000 ether));  // Fund vault2 using ltlf1 for 50m DAI
            assertTrue(sid.try_fundLoan(address(lp1), address(vault2),  address(ltlf1), 50_000_000 ether));  // Fund vault2 using ltlf1 for 50m DAI, again, 100m DAI total
            assertTrue(sid.try_fundLoan(address(lp1), address(vault2),  address(ltlf2), 50_000_000 ether));  // Fund vault2 using ltlf2 for 50m DAI
            assertTrue(sid.try_fundLoan(address(lp1), address(vault2),  address(ltlf2), 50_000_000 ether));  // Fund vault2 using ltlf2 for 50m DAI again, 200m DAI total

            // LP 2 Vault 2
            assertTrue(joe.try_fundLoan(address(lp2), address(vault2),  address(ltlf1), 100_000_000 ether));  // Fund vault2 using ltlf1 for 100m DAI
            assertTrue(joe.try_fundLoan(address(lp2), address(vault2),  address(ltlf1), 100_000_000 ether));  // Fund vault2 using ltlf1 for 100m DAI, again, 400m DAI total
            assertTrue(joe.try_fundLoan(address(lp2), address(vault2),  address(ltlf2), 100_000_000 ether));  // Fund vault2 using ltlf2 for 100m DAI (excess)
            assertTrue(joe.try_fundLoan(address(lp2), address(vault2),  address(ltlf2), 100_000_000 ether));  // Fund vault2 using ltlf2 for 100m DAI (excess), 600m DAI total
        }
        
        LoanTokenLocker ltl1_lp1 = LoanTokenLocker(lp1.loanTokenLockers(address(vault),  address(ltlf1)));  // ltl1_lp1 = LoanTokenLocker 1, for lp1, for vault using ltlf1
        LoanTokenLocker ltl2_lp1 = LoanTokenLocker(lp1.loanTokenLockers(address(vault),  address(ltlf2)));  // ltl2_lp1 = LoanTokenLocker 2, for lp1, for vault using ltlf2
        LoanTokenLocker ltl3_lp1 = LoanTokenLocker(lp1.loanTokenLockers(address(vault2), address(ltlf1)));  // ltl3_lp1 = LoanTokenLocker 3, for lp1, for vault2 using ltlf1
        LoanTokenLocker ltl4_lp1 = LoanTokenLocker(lp1.loanTokenLockers(address(vault2), address(ltlf2)));  // ltl4_lp1 = LoanTokenLocker 4, for lp1, for vault2 using ltlf2
        LoanTokenLocker ltl1_lp2 = LoanTokenLocker(lp2.loanTokenLockers(address(vault),  address(ltlf1)));  // ltl1_lp2 = LoanTokenLocker 1, for lp2, for vault using ltlf1
        LoanTokenLocker ltl2_lp2 = LoanTokenLocker(lp2.loanTokenLockers(address(vault),  address(ltlf2)));  // ltl2_lp2 = LoanTokenLocker 2, for lp2, for vault using ltlf2
        LoanTokenLocker ltl3_lp2 = LoanTokenLocker(lp2.loanTokenLockers(address(vault2), address(ltlf1)));  // ltl3_lp2 = LoanTokenLocker 3, for lp2, for vault2 using ltlf1
        LoanTokenLocker ltl4_lp2 = LoanTokenLocker(lp2.loanTokenLockers(address(vault2), address(ltlf2)));  // ltl4_lp2 = LoanTokenLocker 4, for lp2, for vault2 using ltlf2

        // Present state checks
        assertEq(IERC20(DAI).balanceOf(liqLocker1),              700_000_000 ether);  // 1b DAI deposited - (100m DAI - 200m DAI)
        assertEq(IERC20(DAI).balanceOf(liqLocker2),              500_000_000 ether);  // 1b DAI deposited - (100m DAI - 400m DAI)
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),  200_000_000 ether);  // Balance of vault fl 
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker2)), 600_000_000 ether);  // Balance of vault2 fl (no excess, exactly 400 DAI from LP1 & 600 DAI from LP2)
        assertEq(vault.balanceOf(address(ltl1_lp1)),              50_000_000 ether);  // Balance of ltl1 for lp1 with ltlf1
        assertEq(vault.balanceOf(address(ltl2_lp1)),              50_000_000 ether);  // Balance of ltl2 for lp1 with ltlf2
        assertEq(vault2.balanceOf(address(ltl3_lp1)),            100_000_000 ether);  // Balance of ltl3 for lp1 with ltlf1
        assertEq(vault2.balanceOf(address(ltl4_lp1)),            100_000_000 ether);  // Balance of ltl4 for lp1 with ltlf2
        assertEq(vault.balanceOf(address(ltl1_lp2)),              50_000_000 ether);  // Balance of ltl1 for lp2 with ltlf1
        assertEq(vault.balanceOf(address(ltl2_lp2)),              50_000_000 ether);  // Balance of ltl2 for lp2 with ltlf2
        assertEq(vault2.balanceOf(address(ltl3_lp2)),            200_000_000 ether);  // Balance of ltl3 for lp2 with ltlf1
        assertEq(vault2.balanceOf(address(ltl4_lp2)),            200_000_000 ether);  // Balance of ltl4 for lp2 with ltlf2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  vault.collateralRequiredForDrawdown(500_000_000 ether); // wETH required for 500m DAI drawdown on vault
            uint cReq2 = vault2.collateralRequiredForDrawdown(400_000_000 ether); // wETH required for 500m DAI drawdown on vault2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(vault),  cReq1);
            fay.approve(WETH, address(vault2), cReq2);
            eli.drawdown(address(vault),  100_000_000 ether); // 100m excess to be returned
            fay.drawdown(address(vault2), 300_000_000 ether); // 200m excess to be returned
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
        {
            checkClaim(ltl1_lp1, vault,  sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl2_lp1, vault,  sid, IERC20(DAI), lp1, address(ltlf2));
            checkClaim(ltl3_lp1, vault2, sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl4_lp1, vault2, sid, IERC20(DAI), lp1, address(ltlf2));

            checkClaim(ltl1_lp2, vault,  joe, IERC20(DAI), lp2, address(ltlf1));
            checkClaim(ltl2_lp2, vault,  joe, IERC20(DAI), lp2, address(ltlf2));
            checkClaim(ltl3_lp2, vault2, joe, IERC20(DAI), lp2, address(ltlf1));
            checkClaim(ltl4_lp2, vault2, joe, IERC20(DAI), lp2, address(ltlf2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
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
        {
            checkClaim(ltl1_lp1, vault,  sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl2_lp1, vault,  sid, IERC20(DAI), lp1, address(ltlf2));
            checkClaim(ltl3_lp1, vault2, sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl4_lp1, vault2, sid, IERC20(DAI), lp1, address(ltlf2));

            checkClaim(ltl1_lp2, vault,  joe, IERC20(DAI), lp2, address(ltlf1));
            checkClaim(ltl2_lp2, vault,  joe, IERC20(DAI), lp2, address(ltlf2));
            checkClaim(ltl3_lp2, vault2, joe, IERC20(DAI), lp2, address(ltlf1));
            checkClaim(ltl4_lp2, vault2, joe, IERC20(DAI), lp2, address(ltlf2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
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
        {
            checkClaim(ltl1_lp1, vault,  sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl2_lp1, vault,  sid, IERC20(DAI), lp1, address(ltlf2));
            checkClaim(ltl3_lp1, vault2, sid, IERC20(DAI), lp1, address(ltlf1));
            checkClaim(ltl4_lp1, vault2, sid, IERC20(DAI), lp1, address(ltlf2));

            checkClaim(ltl1_lp2, vault,  joe, IERC20(DAI), lp2, address(ltlf1));
            checkClaim(ltl2_lp2, vault,  joe, IERC20(DAI), lp2, address(ltlf2));
            checkClaim(ltl3_lp2, vault2, joe, IERC20(DAI), lp2, address(ltlf1));
            checkClaim(ltl4_lp2, vault2, joe, IERC20(DAI), lp2, address(ltlf2));

            // Ensure both loans are matured.
            assertEq(uint256(vault.loanState()),  2);
            assertEq(uint256(vault2.loanState()), 2);
        }
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
        bob.withdraw(address(lp1), lp1.balanceOf(address(bob)));
        assertEq(IERC20(DAI).balanceOf(address(bob)), 100 ether); // Paid back initial share of 10% of pool

        // TODO: Post-claim, multiple providers
    }
}
