// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/LP.sol";
import "./user/Staker.sol";
import "./user/Commoner.sol";
import "./user/PoolDelegate.sol";
import "./user/PoolAdmin.sol";
import "./user/EmergencyAdmin.sol";

import "../interfaces/IBFactory.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IStakeLocker.sol";

import "../LateFeeCalc.sol";

import "../RepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../DebtLocker.sol";
import "../DebtLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../Loan.sol";
import "../LoanFactory.sol";
import "../Pool.sol";
import "../PoolFactory.sol";
import "../PremiumCalc.sol";
import "../StakeLockerFactory.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "module/maple-token/contracts/MapleToken.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Treasury { }

contract PoolTest is TestUtil {

    using SafeMath for uint256;

    Borrower                               eli;
    Borrower                               fay;
    Borrower                               hal;
    Governor                               gov;
    LP                                     bob;
    LP                                     che;
    LP                                     dan;
    LP                                     kim;
    Staker                                 buf;
    Commoner                               com;
    PoolDelegate                           sid;
    PoolDelegate                           joe;
    PoolAdmin                              pop;
    EmergencyAdmin                         mic;

    RepaymentCalc                repaymentCalc;
    CollateralLockerFactory          clFactory;
    DebtLockerFactory               dlFactory1;
    DebtLockerFactory               dlFactory2;
    FundingLockerFactory             flFactory;
    LateFeeCalc                    lateFeeCalc;
    LiquidityLockerFactory           llFactory;
    Loan                                  loan;
    Loan                                 loan2;
    Loan                                 loan3;
    Loan                                 loan4;
    LoanFactory                    loanFactory;
    MapleGlobals                       globals;
    MapleToken                             mpl;
    PoolFactory                    poolFactory;
    Pool                                 pool1;
    Pool                                 pool2;
    Pool                                 pool3;
    PremiumCalc                    premiumCalc;
    StakeLockerFactory               slFactory;
    Treasury                               trs;
    ChainlinkOracle                 wethOracle;
    ChainlinkOracle                 wbtcOracle;
    UsdOracle                        usdOracle;
    
    ERC20                           fundsToken;
    IBPool                               bPool;

    function setUp() public {

        eli            = new Borrower();                                                // Actor: Borrower of the Loan.
        fay            = new Borrower();                                                // Actor: Borrower of the Loan.
        hal            = new Borrower();                                                // Actor: Borrower of the Loan.
        gov            = new Governor();                                                // Actor: Governor of Maple.
        bob            = new LP();                                                      // Actor: Liquidity provider.
        che            = new LP();                                                      // Actor: Liquidity provider.
        dan            = new LP();                                                      // Actor: Liquidity provider.
        kim            = new LP();                                                      // Actor: Liquidity provider.
        buf            = new Staker();                                                  // Actor: Stakes BPTs in Pool.
        com            = new Commoner();                                                // Actor: Any user or an incentive seeker.                                            // Actor: Manager of the Pool.
        sid            = new PoolDelegate();                                            // Actor: Manager of the Pool.
        joe            = new PoolDelegate();                                            // Actor: Manager of the Pool.
        pop            = new PoolAdmin();                                               // Actor: Admin of the Pool.
        mic            = new EmergencyAdmin();                                          // Actor: Emergency Admin of the protocol.

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl));
        flFactory      = new FundingLockerFactory();                                    // Setup the FL factory to facilitate Loan factory functionality.
        clFactory      = new CollateralLockerFactory();                                 // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory    = new LoanFactory(address(globals));                             // Create Loan factory.
        slFactory      = new StakeLockerFactory();                                      // Setup the SL factory to facilitate Pool factory functionality.
        llFactory      = new LiquidityLockerFactory();                                  // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory    = new PoolFactory(address(globals));                             // Create pool factory.
        dlFactory1     = new DebtLockerFactory();                                       // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        dlFactory2     = new DebtLockerFactory();                                       // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        repaymentCalc  = new RepaymentCalc();                                           // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                                            // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);                                          // Flat 5% premium
        trs            = new Treasury();                                                // Treasury.

        /*** Validate all relevant contracts in Globals ***/
        gov.setValidLoanFactory(address(loanFactory), true);
        gov.setValidPoolFactory(address(poolFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory1), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory2), true);

        wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        usdOracle  = new UsdOracle();
        
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * USD);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool), MAX_UINT);

        bPool.bind(USDC, 50_000_000 * USD, 5 ether);       // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl), 100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * USD);
        assertEq(mpl.balanceOf(address(bPool)),             100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized

        gov.setPoolDelegateAllowlist(address(sid), true);
        gov.setPoolDelegateAllowlist(address(joe), true);
        gov.setMapleTreasury(address(trs));
        gov.setAdmin(address(mic));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), bPool.balanceOf(address(this)) / 2);
        bPool.transfer(address(joe), bPool.balanceOf(address(this)));

        gov.setValidBalancerPool(address(bPool), true);

        // Set Globals
        gov.setCalc(address(repaymentCalc),  true);
        gov.setCalc(address(lateFeeCalc),    true);
        gov.setCalc(address(premiumCalc),    true);
        gov.setCollateralAsset(WETH,         true);
        gov.setLoanAsset(USDC,               true);
        gov.setSwapOutRequired(1_000_000);

        // Create Liquidity Pool
        pool1 = Pool(sid.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT  // liquidityCap value
        ));

        // Create Liquidity Pool
        pool2 = Pool(joe.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            7500,
            50,
            MAX_UINT // liquidityCap value
        ));

        // loan Specifications
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        loan  = eli.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan2 = fay.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan3 = hal.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
    }

    function test_claim_permissions() public {
        
        // Set valid loan factory
        gov.setValidLoanFactory(address(loanFactory), true);
        // Finalizing the Pool
        sid.approve(address(bPool), pool1.stakeLocker(), uint(-1));
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        sid.finalize(address(pool1));

        // Add liquidity into the pool (Dan is an LP, but still won't be able to claim)
        mint("USDC", address(dan), 10_000 * USD);
        dan.approve(USDC, address(pool1), 10_000 * USD);
        sid.setOpenToPublic(address(pool1), true);
        assertTrue(dan.try_deposit(address(pool1), 10_000 * USD));

        // Fund Loan (so that debtLocker is instantiated and given LoanFDTs)
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 10_000 * USD));
        
        // Assert that LPs and non-admins cannot claim
        assertTrue(!dan.try_claim(address(pool1), address(loan), address(dlFactory1)));  // Does not have permission to call `claim()` function
        assertTrue(!pop.try_claim(address(pool1), address(loan), address(dlFactory1)));  // Does not have permission to call `claim()` function

        // Pool delegate can claim
        assertTrue(sid.try_claim(address(pool1), address(loan), address(dlFactory1)));   // Successfully call the `claim()` function
        
        // Admin can claim once added
        sid.setAdmin(address(pool1), address(pop), true);                                // Add admin to allow to call the `claim()` function
        assertTrue(pop.try_claim(address(pool1), address(loan), address(dlFactory1)));   // Successfully call the `claim()` function

        // Pause protocol and attempt claim()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!pop.try_claim(address(pool1), address(loan), address(dlFactory1)));
        
        // Unpause protocol and claim()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(pop.try_claim(address(pool1), address(loan), address(dlFactory1)));

        // Admin can't claim after removed
        sid.setAdmin(address(pool1), address(pop), false);                                // Add admin to allow to call the `claim()` function
        assertTrue(!pop.try_claim(address(pool1), address(loan), address(dlFactory1)));   // Does not have permission to call `claim()` function
    }

    function test_getInitialStakeRequirements() public {
        uint256 minCover; uint256 minCover2; uint256 curCover;
        uint256 minStake; uint256 minStake2; uint256 curStake;
        uint256 calc_minStake; uint256 calc_stakerBal;
        bool covered;

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        address stakeLocker = pool1.stakeLocker();
        sid.approve(address(bPool), stakeLocker, MAX_UINT);

        // Pre-state checks.
        assertEq(bPool.balanceOf(address(sid)),                 50 * WAD);  // PD has 50 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                         0);  // Nothing staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),          0);  // Nothing staked

        (minCover, curCover, covered, minStake, curStake) = pool1.getInitialStakeRequirements();

        (calc_minStake, calc_stakerBal) = pool1.getPoolSharesRequired(address(bPool), USDC, address(sid), stakeLocker, minCover);

        assertEq(minCover, globals.swapOutRequired() * USD);              // Equal to globally specified value
        assertEq(curCover, 0);                                            // Nothing staked
        assertTrue(!covered);                                             // Not covered
        assertEq(minStake, calc_minStake);                                // Mininum stake equals calculated minimum stake     
        assertEq(curStake, calc_stakerBal);                               // Current stake equals calculated stake
        assertEq(curStake, IERC20(stakeLocker).balanceOf(address(sid)));  // Current stake equals balance of stakeLocker FDTs

        /***************************************/
        /*** Stake Less than Required Amount ***/
        /***************************************/
        sid.stake(stakeLocker, minStake - 1);

        // Post-state checks.
        assertEq(bPool.balanceOf(address(sid)),                50 * WAD - (minStake - 1));  // PD staked minStake - 1 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                             minStake - 1);   // minStake - 1 BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),              minStake - 1);   // PD has minStake - 1 SL tokens

        (minCover2, curCover, covered, minStake2, curStake) = pool1.getInitialStakeRequirements();

        (, calc_stakerBal) = pool1.getPoolSharesRequired(address(bPool), USDC, address(sid), stakeLocker, minCover);

        assertEq(minCover2, minCover);                                    // Doesn't change
        assertTrue(curCover < minCover);                                  // Not enough cover
        assertTrue(!covered);                                             // Not covered
        assertEq(minStake2, minStake);                                    // Doesn't change
        assertEq(curStake, calc_stakerBal);                               // Current stake equals calculated stake
        assertEq(curStake, IERC20(stakeLocker).balanceOf(address(sid)));  // Current stake equals balance of stakeLocker FDTs

        /***********************************/
        /*** Stake Exact Required Amount ***/
        /***********************************/
        sid.stake(stakeLocker, 1); // Add one more wei of BPT to get to minStake amount

        // Post-state checks.
        assertEq(bPool.balanceOf(address(sid)),                50 * WAD - minStake);  // PD staked minStake
        assertEq(bPool.balanceOf(stakeLocker),                            minStake);  // minStake BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),             minStake);  // PD has minStake SL tokens

        (minCover2, curCover, covered, minStake2, curStake) = pool1.getInitialStakeRequirements();

        (, calc_stakerBal) = pool1.getPoolSharesRequired(address(bPool), USDC, address(sid), stakeLocker, minCover);

        assertEq(minCover2, minCover);                                    // Doesn't change
        withinPrecision(curCover, minCover, 6);                           // Roughly enough
        assertTrue(covered);                                              // Covered
        assertEq(minStake2, minStake);                                    // Doesn't change
        assertEq(curStake, calc_stakerBal);                               // Current stake equals calculated stake
        assertEq(curStake, IERC20(stakeLocker).balanceOf(address(sid)));  // Current stake equals balance of stakeLocker FDTs
    }

    function test_stake_and_finalize() public {

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        address stakeLocker = pool1.stakeLocker();
        sid.approve(address(bPool), stakeLocker, uint(-1));

        // Pre-state checks.
        assertEq(bPool.balanceOf(address(sid)),                 50 * WAD);  // PD has 50 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                         0);  // Nothing staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),          0);  // Nothing staked

        /***************************************/
        /*** Stake Less than Required Amount ***/
        /***************************************/
        (,,, uint256 minStake,) = pool1.getInitialStakeRequirements();
        sid.stake(pool1.stakeLocker(), minStake - 1);

        // Post-state checks.
        assertEq(bPool.balanceOf(address(sid)),                50 * WAD - (minStake - 1));  // PD staked minStake - 1 BPTs
        assertEq(bPool.balanceOf(stakeLocker),                             minStake - 1);   // minStake - 1 BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),              minStake - 1);   // PD has minStake - 1 SL tokens

        assertTrue(!sid.try_finalize(address(pool1)));  // Can't finalize

        /***********************************/
        /*** Stake Exact Required Amount ***/
        /***********************************/
        sid.stake(stakeLocker, 1); // Add one more wei of BPT to get to minStake amount

        // Post-state checks.
        assertEq(bPool.balanceOf(address(sid)),                50 * WAD - minStake);  // PD staked minStake
        assertEq(bPool.balanceOf(stakeLocker),                            minStake);  // minStake BPTs staked
        assertEq(IERC20(stakeLocker).balanceOf(address(sid)),             minStake);  // PD has minStake SL tokens
        assertEq(uint256(pool1.poolState()), 0);  // Initialized

        assertTrue(!joe.try_finalize(address(pool1)));  // Can't finalize if not PD

        // Pause protocol and attempt finalize()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_finalize(address(pool1)));
        
        // Unpause protocol and finalize()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_finalize(address(pool1)));  // PD that staked can finalize

        assertEq(uint256(pool1.poolState()), 1);  // Finalized
    }

    function test_deposit() public {
        address stakeLocker = pool1.stakeLocker();
        address liqLocker   = pool1.liquidityLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        // Mint 100 USDC into this LP account
        mint("USDC", address(bob), 100 * USD);

        assertTrue(!bob.try_deposit(address(pool1), 100 * USD)); // Not finalized

        sid.finalize(address(pool1));

        assertTrue(!pool1.openToPublic());
        assertTrue(!pool1.allowedLiquidityProviders(address(bob)));
        assertTrue(  !bob.try_deposit(address(pool1), 100 * USD)); // Not in the LP allow list neither the pool is open to public.

        assertTrue( !joe.try_setAllowList(address(pool1), address(bob), true)); // It will fail as `joe` is not the right PD.
        assertTrue(  sid.try_setAllowList(address(pool1), address(bob), true));
        assertTrue(pool1.allowedLiquidityProviders(address(bob)));
        
        assertTrue(!bob.try_deposit(address(pool1), 100 * USD)); // Not Approved

        bob.approve(USDC, address(pool1), MAX_UINT);

        assertEq(IERC20(USDC).balanceOf(address(bob)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(liqLocker),            0);
        assertEq(pool1.balanceOf(address(bob)),                0);

        assertTrue(bob.try_deposit(address(pool1),    100 * USD));

        assertEq(IERC20(USDC).balanceOf(address(bob)),         0);
        assertEq(IERC20(USDC).balanceOf(liqLocker),    100 * USD);
        assertEq(pool1.balanceOf(address(bob)),        100 * WAD);

        // Remove bob from the allowed list
        assertTrue(sid.try_setAllowList(address(pool1), address(bob), false));
        mint("USDC", address(bob), 100 * USD);
        assertTrue(!bob.try_deposit(address(pool1),    100 * USD));

        mint("USDC", address(dan), 200 * USD);
        dan.approve(USDC, address(pool1), MAX_UINT);
        
        assertEq(IERC20(USDC).balanceOf(address(dan)), 200 * USD);
        assertEq(IERC20(USDC).balanceOf(liqLocker),    100 * USD);
        assertEq(pool1.balanceOf(address(dan)),                0);

        assertTrue(!pool1.allowedLiquidityProviders(address(dan)));
        assertTrue(  !dan.try_deposit(address(pool1),  100 * USD)); // Fail to invest as dan is not in the allowed list.

        // Pause protocol and attempt openPoolToPublic()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_setOpenToPublic(address(pool1), true));

        // Unpause protocol and openPoolToPublic()
        assertTrue( mic.try_setProtocolPause(address(globals), false));
        assertTrue(!joe.try_setOpenToPublic(address(pool1), true));  // Incorrect PD.
        assertTrue( sid.try_setOpenToPublic(address(pool1), true));

        assertTrue(dan.try_deposit(address(pool1),     100 * USD));

        assertEq(IERC20(USDC).balanceOf(address(dan)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(liqLocker),    200 * USD);
        assertEq(pool1.balanceOf(address(dan)),        100 * WAD);

        mint("USDC", address(bob), 200 * USD);

        // Pool-specific pause by Pool Delegate via setLiquidityCap(0)
        assertEq( pool1.liquidityCap(), MAX_UINT);
        assertTrue(!com.try_setLiquidityCap(address(pool1), 0));
        assertTrue( sid.try_setLiquidityCap(address(pool1), 0));
        assertEq( pool1.liquidityCap(), 0);
        assertTrue(!bob.try_deposit(address(pool1), 1 * USD));
        assertTrue( sid.try_setLiquidityCap(address(pool1), MAX_UINT));
        assertEq( pool1.liquidityCap(), MAX_UINT);
        assertTrue( bob.try_deposit(address(pool1), 100 * USD));
        assertEq( pool1.balanceOf(address(bob)), 200 * WAD);
 
        // Protocol-wide pause by Emergency Admin
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!bob.try_deposit(address(pool1), 1 * USD));
        assertTrue( mic.try_setProtocolPause(address(globals), false));
        assertTrue( bob.try_deposit(address(pool1),100 * USD));
        assertEq( pool1.balanceOf(address(bob)), 300 * WAD);

        // Pause protocol and attempt setLiquidityCap()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_setLiquidityCap(address(pool1), MAX_UINT));

        // Unpause protocol and setLiquidityCap()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_setLiquidityCap(address(pool1), MAX_UINT));

        assertTrue(sid.try_setOpenToPublic(address(pool1), false));  // Close pool to public
        assertTrue(!dan.try_deposit(address(pool1),    100 * USD));  // Fail to deposit as pool no longer public
    }

    function test_setLockupPeriod() public {
        assertEq(pool1.lockupPeriod(), 180 days);
        assertTrue(!joe.try_setLockupPeriod(address(pool1), 15 days));       // Cannot set lockup period if not pool delegate
        assertTrue(!sid.try_setLockupPeriod(address(pool1), 180 days + 1));  // Cannot increase lockup period
        assertTrue( sid.try_setLockupPeriod(address(pool1), 180 days));      // Can set the same lockup period
        assertTrue( sid.try_setLockupPeriod(address(pool1), 180 days - 1));  // Can decrease lockup period
        assertEq(pool1.lockupPeriod(), 180 days - 1);
        assertTrue(!sid.try_setLockupPeriod(address(pool1), 180 days));      // Cannot increase lockup period

        // Pause protocol and attempt setLockupPeriod()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_setLockupPeriod(address(pool1), 180 days - 2));
        assertEq(pool1.lockupPeriod(), 180 days - 1);

        // Unpause protocol and setLockupPeriod()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_setLockupPeriod(address(pool1), 180 days - 2));
        assertEq(pool1.lockupPeriod(), 180 days - 2);
    }

    function test_deposit_with_liquidity_cap() public {
    
        address stakeLocker = pool1.stakeLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        // Mint 1000 USDC into this LP account
        mint("USDC", address(bob), 10000 * USD);

        sid.finalize(address(pool1));
        sid.setPrincipalPenalty(address(pool1), 0);
        sid.setOpenToPublic(address(pool1), true);

        bob.approve(USDC, address(pool1), MAX_UINT);

        // Changes the `liquidityCap`.
        assertTrue(sid.try_setLiquidityCap(address(pool1), 900 * USD), "Failed to set liquidity cap");
        assertEq(pool1.liquidityCap(), 900 * USD, "Incorrect value set for liquidity cap");

        // Not able to deposit as cap is lower than the deposit amount.
        assertTrue(!pool1.isDepositAllowed(1000 * USD), "Deposit should not be allowed because 900 USD < 1000 USD");
        assertTrue(!bob.try_deposit(address(pool1), 1000 * USD), "Should not able to deposit 1000 USD");

        // Tries with lower amount it will pass.
        assertTrue(pool1.isDepositAllowed(500 * USD), "Deposit should be allowed because 900 USD > 500 USD");
        assertTrue(bob.try_deposit(address(pool1), 500 * USD), "Fail to deposit 500 USD");

        // Bob tried again with 600 USDC it fails again.
        assertTrue(!pool1.isDepositAllowed(600 * USD), "Deposit should not be allowed because 900 USD < 500 + 600 USD");
        assertTrue(!bob.try_deposit(address(pool1), 600 * USD), "Should not able to deposit 600 USD");

        // Set liquidityCap to zero and withdraw
        assertTrue(sid.try_setLiquidityCap(address(pool1), 0),  "Failed to set liquidity cap");
        assertTrue(sid.try_setLockupPeriod(address(pool1), 0),  "Failed to set the lockup period");
        assertEq(pool1.lockupPeriod(), uint256(0),              "Failed to update the lockup period");
        
        (uint claimable,,) = pool1.claimableFunds(address(bob));

        uint256 currentTime = block.timestamp;

        assertEq(claimable, 500 * USD);
        assertTrue(!bob.try_withdraw(address(pool1), claimable),    "Should fail to withdraw 500 USD because user has to show the intend first");
        assertTrue(!dan.try_intendToWithdraw(address(pool1)),       "Failed to show intend to withdraw because dan has zero pool FDTs");
        assertTrue( bob.try_intendToWithdraw(address(pool1)),       "Failed to show intend to withdraw");
        assertEq( pool1.depositCooldown(address(bob)), currentTime, "Incorrect value set");
        assertTrue(!bob.try_withdraw(address(pool1), claimable),    "Should fail to withdraw as cool down period hasn't passed yet");

        hevm.warp(currentTime + globals.cooldownPeriod() - 1);
        assertTrue(!bob.try_withdraw(address(pool1), claimable), "Should fail to withdraw as cool down period hasn't passed yet");
        hevm.warp(currentTime + globals.cooldownPeriod());
        assertTrue(!bob.try_withdraw(address(pool1), claimable), "Should fail to withdraw as cool down period hasn't passed yet");
        hevm.warp(currentTime + globals.cooldownPeriod() + 1);
        assertTrue(bob.try_withdraw(address(pool1), claimable),  "Should pass to withdraw the funds from the pool");
    }

    function make_withdrawable(LP investor, Pool pool) public {
        uint256 currentTime = block.timestamp;
        assertTrue(investor.try_intendToWithdraw(address(pool)));
        assertEq(      pool.depositCooldown(address(investor)), currentTime, "Incorrect value set");
        hevm.warp(currentTime + globals.cooldownPeriod() + 1);
    }

    function test_deposit_depositDate() public {
        address stakeLocker = pool1.stakeLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);
        sid.setOpenToPublic(address(pool1), true);
        
        // Mint 100 USDC into this LP account
        mint("USDC", address(bob), 200 * USD);
        bob.approve(USDC, address(pool1), MAX_UINT);
        sid.finalize(address(pool1));

        // Deposit 100 USDC on first day
        uint256 startDate = block.timestamp;

        uint256 initialAmt = 100 * USD;

        bob.deposit(address(pool1), 100 * USD);
        assertEq(pool1.depositDate(address(bob)), startDate);

        uint256 newAmt = 20 * USD;

        hevm.warp(startDate + 30 days);
        bob.deposit(address(pool1), newAmt);

        uint256 newDepDate = startDate + (block.timestamp - startDate) * newAmt / (newAmt + initialAmt);
        assertEq(pool1.depositDate(address(bob)), newDepDate);  // Gets updated

        assertTrue(sid.try_setLockupPeriod(address(pool1), uint256(0)));  // Sets 0 as lockup period to allow withdraw. 
        make_withdrawable(bob, pool1);
        bob.withdraw(address(pool1), newAmt);

        assertEq(pool1.depositDate(address(bob)), newDepDate);  // Doesn't change
    }

    function test_transfer_depositDate() public {
        address stakeLocker = pool1.stakeLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);
        sid.finalize(address(pool1));
        sid.setOpenToPublic(address(pool1), true);
        
        // Mint 200 USDC into this LP account
        mint("USDC", address(bob), 200 * USD);
        mint("USDC", address(che), 200 * USD);
        bob.approve(USDC, address(pool1), MAX_UINT);
        che.approve(USDC, address(pool1), MAX_UINT);
        
        // Deposit 100 USDC on first day
        uint256 startDate = block.timestamp;

        uint256 initialAmt = 100 * WAD;  // Amount of FDT minted on first deposit

        bob.deposit(address(pool1), 100 * USD);
        che.deposit(address(pool1), 100 * USD);
        
        assertEq(pool1.depositDate(address(bob)), startDate);
        assertEq(pool1.depositDate(address(che)), startDate);

        uint256 newAmt = 20 * WAD;  // Amount of FDT transferred

        hevm.warp(startDate + 30 days);

        assertEq(pool1.balanceOf(address(bob)), initialAmt);
        assertEq(pool1.balanceOf(address(che)), initialAmt);

        make_withdrawable(che, pool1);

        // Pause protocol and attempt to transfer FDTs
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!che.try_transfer(address(pool1), address(bob), newAmt));

        // Unpause protocol and transfer FDTs
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(che.try_transfer(address(pool1), address(bob), newAmt));  // Pool.transfer()

        assertEq(pool1.balanceOf(address(bob)), initialAmt + newAmt);
        assertEq(pool1.balanceOf(address(che)), initialAmt - newAmt);

        uint256 newDepDate = startDate + (block.timestamp - startDate) * newAmt / (newAmt + initialAmt);

        assertEq(pool1.depositDate(address(bob)), newDepDate);  // Gets updated
        assertEq(pool1.depositDate(address(che)),  startDate);  // Stays the same
    }

    function test_fundLoan() public {
        address stakeLocker   = pool1.stakeLocker();
        address liqLocker     = pool1.liquidityLocker();
        address fundingLocker = loan.fundingLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        // Mint 100 USDC into this LP account
        mint("USDC", address(bob), 100 * USD);

        sid.finalize(address(pool1));
        sid.setOpenToPublic(address(pool1), true);

        bob.approve(USDC, address(pool1), MAX_UINT);

        assertTrue(bob.try_deposit(address(pool1), 100 * USD));

        gov.setValidLoanFactory(address(loanFactory), false);

        assertTrue(!sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 100 * USD)); // LoanFactory not in globals

        gov.setValidLoanFactory(address(loanFactory), true);

        assertEq(IERC20(USDC).balanceOf(liqLocker),               100 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),          0);  // Balance of Funding Locker
        
        /*******************/
        /*** Fund a Loan ***/
        /*******************/
        // Pause protocol and attempt fundLoan()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 1 * USD));

        // Unpause protocol and fundLoan()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 20 * USD), "Fail to fund a loan");  // Fund loan for 20 USDC

        DebtLocker debtLocker = DebtLocker(pool1.debtLockers(address(loan), address(dlFactory1)));

        assertEq(address(debtLocker.loan()), address(loan));
        assertEq(debtLocker.pool(), address(pool1));
        assertEq(address(debtLocker.loanAsset()), USDC);

        assertEq(IERC20(USDC).balanceOf(liqLocker),              80 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 20 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),    20 * WAD);  // LoanToken balance of LT Locker
        assertEq(pool1.principalOut(),                           20 * USD);  // Outstanding principal in liqiudity pool 1

        /****************************************/
        /*** Fund same loan with the same DL ***/
        /****************************************/
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 25 * USD)); // Fund same loan for 25 USDC

        assertEq(dlFactory1.owner(address(debtLocker)), address(pool1));
        assertTrue(dlFactory1.isLocker(address(debtLocker)));

        assertEq(IERC20(USDC).balanceOf(liqLocker),              55 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 45 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),    45 * WAD);  // LoanToken balance of LT Locker
        assertEq(pool1.principalOut(),                           45 * USD);  // Outstanding principal in liqiudity pool 1

        /*******************************************/
        /*** Fund same loan with a different DL ***/
        /*******************************************/
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory2), 10 * USD)); // Fund loan for 15 USDC

        DebtLocker debtLocker2 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory2)));

        assertEq(address(debtLocker2.loan()), address(loan));
        assertEq(debtLocker2.pool(), address(pool1));
        assertEq(address(debtLocker2.loanAsset()), USDC);

        assertEq(dlFactory2.owner(address(debtLocker2)), address(pool1));
        assertTrue(dlFactory2.isLocker(address(debtLocker2)));

        assertEq(IERC20(USDC).balanceOf(liqLocker),              45 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 55 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker2)),   10 * WAD);  // LoanToken balance of LT Locker 2
        assertEq(pool1.principalOut(),                           55 * USD);  // Outstanding principal in liqiudity pool 1
    }

    function checkClaim(DebtLocker debtLocker, Loan _loan, PoolDelegate pd, IERC20 liquidityAsset, Pool pool, address dlFactory) internal {
        uint256[10] memory balances = [
            liquidityAsset.balanceOf(address(debtLocker)),
            liquidityAsset.balanceOf(address(pool)),
            liquidityAsset.balanceOf(address(pd)),
            liquidityAsset.balanceOf(pool.stakeLocker()),
            liquidityAsset.balanceOf(pool.liquidityLocker()),
            0,0,0,0,0
        ];

        uint256[4] memory loanData = [
            _loan.interestPaid(),
            _loan.principalPaid(),
            _loan.feePaid(),
            _loan.excessReturned()
        ];

        uint256[8] memory debtLockerData = [
            debtLocker.interestPaid(),
            debtLocker.principalPaid(),
            debtLocker.feePaid(),
            debtLocker.excessReturned(),
            0,0,0,0
        ];

        uint256 beforePrincipalOut = pool.principalOut();
        uint256 beforeInterestSum  = pool.interestSum();
        uint256[7] memory claim = pd.claim(address(pool), address(_loan),   address(dlFactory));

        // Updated DL state variables
        debtLockerData[4] = debtLocker.interestPaid();
        debtLockerData[5] = debtLocker.principalPaid();
        debtLockerData[6] = debtLocker.feePaid();
        debtLockerData[7] = debtLocker.excessReturned();

        balances[5] = liquidityAsset.balanceOf(address(debtLocker));
        balances[6] = liquidityAsset.balanceOf(address(pool));
        balances[7] = liquidityAsset.balanceOf(address(pd));
        balances[8] = liquidityAsset.balanceOf(pool.stakeLocker());
        balances[9] = liquidityAsset.balanceOf(pool.liquidityLocker());

        uint256 sumTransfer;
        uint256 sumNetNew;

        for(uint i = 0; i < 4; i++) sumNetNew += (loanData[i] - debtLockerData[i]);

        {
            for(uint i = 0; i < 4; i++) {
                assertEq(debtLockerData[i + 4], loanData[i]);  // DL updated to reflect loan state
                // Category portion of claim * DL asset balance 
                // Eg. (interestClaimed / totalClaimed) * balance = Portion of total claim balance that is interest
                uint256 loanShare = (loanData[i] - debtLockerData[i]) * claim[0] / sumNetNew;
                assertEq(loanShare, claim[i + 1]);

                sumTransfer += balances[i + 6] - balances[i + 1]; // Sum up all transfers that occured from claim
            }
            assertEq(claim[0], sumTransfer); // Assert balance from withdrawFunds equals sum of transfers
        }

        {
            assertEq(balances[5] - balances[0], 0);      // DL locker should have transferred ALL funds claimed to LP
            assertTrue(balances[6] - balances[1] < 10);  // LP        should have transferred ALL funds claimed to LL, SL, and PD (with rounding error)
            assertEq(balances[7] - balances[2], claim[3] + claim[1] * pool.delegateFee() / 10_000);  // Pool delegate claim (feePaid + delegateFee portion of interest)
            assertEq(balances[8] - balances[3],            claim[1] * pool.stakingFee()  / 10_000);  // Staking Locker claim (feePaid + stakingFee portion of interest)

            // Liquidity Locker balance change should EXACTLY equal state variable change
            assertEq(balances[9] - balances[4], (beforePrincipalOut - pool.principalOut()) + (pool.interestSum() - beforeInterestSum));

            // Normal case, principalClaim <= principalOut
            if (claim[2] + claim[4] <= beforePrincipalOut) {
                // interestSum incremented by remainder of interest
                withinPrecision(
                    pool.interestSum() - beforeInterestSum, 
                    claim[1] - claim[1] * (pool.delegateFee() + pool.stakingFee()) / 10_000, 
                    11
                );  
                // principalOut decremented by principal paid plus excess
                assertTrue(beforePrincipalOut - pool.principalOut() == claim[2] + claim[4]);
            } 
            // Edge case, attacker transfers funds into Loan to make principalClaim overflow
            else {
                // interestSum incremented by remainder of interest plus overflow amount
                withinPrecision(
                    pool.interestSum() - beforeInterestSum, 
                    claim[1] - claim[1] * (pool.delegateFee() + pool.stakingFee()) / 10_000 + (claim[2] + claim[4] - beforePrincipalOut), 
                    11
                );
                assertEq(pool.principalOut(), 0);
            }   
            
        }
    }

    function isConstantPoolValue(Pool pool, IERC20 loanAsset, uint256 constPoolVal) internal view returns(bool) {
        return pool.principalOut() + loanAsset.balanceOf(pool.liquidityLocker()) == constPoolVal;
    }

    function assertConstFundLoan(Pool pool, address _loan, address dlFactory, uint256 amt, IERC20 loanAsset, uint256 constPoolVal) internal returns(bool) {
        assertTrue(sid.try_fundLoan(address(pool), _loan,  dlFactory, amt));
        assertTrue(isConstantPoolValue(pool1, loanAsset, constPoolVal));
    }

    function assertConstClaim(Pool pool, address _loan, address dlFactory, IERC20 loanAsset, uint256 constPoolVal) internal returns(bool) {
        sid.claim(address(pool), _loan, dlFactory);
        assertTrue(isConstantPoolValue(pool, loanAsset, constPoolVal));
    }

    function test_claim_defaulted_zero_collateral_loan() public {
        // Mint 10000 USDC into this LP account
        mint("USDC", address(dan), 10_000 * USD);
        dan.approve(USDC, address(pool1), 10_000 * USD);

        // Set valid loan factory
        gov.setValidLoanFactory(address(loanFactory), true);

        // Finalizing the Pool
        sid.approve(address(bPool), pool1.stakeLocker(), uint(-1));
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);
        sid.finalize(address(pool1));
        sid.setOpenToPublic(address(pool1), true);

        // Add liquidity
        assertTrue(dan.try_deposit(address(pool1), 10_000 * USD));

        // Create Loan with 0% CR so no claimable funds are present after default
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 0, 7];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan zero_loan = eli.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        // Fund the loan by pool delegate.
        assertTrue(sid.try_fundLoan(address(pool1), address(zero_loan), address(dlFactory1), 10_000 * USD));

        // Drawdown of the loan
        uint cReq = zero_loan.collateralRequiredForDrawdown(10_000 * USD); // wETH required for 15000 USDC drawdown on loan
        assertEq(cReq, 0); // No collateral required on 0% collateralized loan
        mint("WETH", address(eli), cReq);
        eli.approve(WETH, address(zero_loan),  cReq);
        eli.drawdown(address(zero_loan), 10_000 * USD);

        // Initial claim to clear out claimable funds
        uint256[7] memory claim = sid.claim(address(pool1), address(zero_loan), address(dlFactory1));

        // Time warp to default
        hevm.warp(block.timestamp + zero_loan.nextPaymentDue() + globals.gracePeriod() + 1);
        sid.triggerDefault(address(pool1), address(zero_loan), address(dlFactory1));   // Triggers a "liquidation" that does not perform a swap

        uint256[7] memory claim2 = sid.claim(address(pool1), address(zero_loan), address(dlFactory1));
        assertEq(claim2[0], 0);
        assertEq(claim2[1], 0);
        assertEq(claim2[2], 0);
        assertEq(claim2[3], 0);
        assertEq(claim2[4], 0);
        assertEq(claim2[5], 0);
        assertEq(claim2[6], 10_000 * USD);
    }

    function test_claim_principal_accounting() public {
        /*********************************************/
        /*** Create a loan with 0% APR, 0% premium ***/
        /*********************************************/
        premiumCalc = new PremiumCalc(0); // Flat 0% premium
        gov.setCalc(address(premiumCalc), true);

        uint256[6] memory specs = [0, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        loan  = eli.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan2 = fay.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            sid.approve(address(bPool), pool1.stakeLocker(), uint(-1));
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

            sid.finalize(address(pool1));
            sid.setOpenToPublic(address(pool1), true);
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("USDC", address(bob), 1_000_000_000 * USD);
            mint("USDC", address(che), 1_000_000_000 * USD);
            mint("USDC", address(dan), 1_000_000_000 * USD);

            bob.approve(USDC, address(pool1), uint(-1));
            che.approve(USDC, address(pool1), uint(-1));
            dan.approve(USDC, address(pool1), uint(-1));

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 * USD));  // 10%
            assertTrue(che.try_deposit(address(pool1), 300_000_000 * USD));  // 30%
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 * USD));  // 60%

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        uint256 CONST_POOL_VALUE = pool1.principalOut() + IERC20(USDC).balanceOf(pool1.liquidityLocker());

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertConstFundLoan(pool1, address(loan),  address(dlFactory1), 100_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan),  address(dlFactory1), 100_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan),  address(dlFactory2), 200_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan),  address(dlFactory2), 200_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan2), address(dlFactory1),  50_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan2), address(dlFactory1),  50_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan2), address(dlFactory2), 150_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
            assertConstFundLoan(pool1, address(loan2), address(dlFactory2), 150_000_000 * USD, IERC20(USDC), CONST_POOL_VALUE);
        }
        
        assertEq(pool1.principalOut(), 1_000_000_000 * USD);
        assertEq(IERC20(USDC).balanceOf(pool1.liquidityLocker()), 0);

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(loan),  cReq1);
            fay.approve(WETH, address(loan2), cReq2);
            eli.drawdown(address(loan),  100_000_000 * USD);
            fay.drawdown(address(loan2), 100_000_000 * USD);
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // USDC required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amtf_1);
            mint("USDC", address(fay), amtf_2);
            eli.approve(USDC, address(loan),  amtf_1);
            fay.approve(USDC, address(loan2), amtf_2);
            eli.makeFullPayment(address(loan));
            fay.makeFullPayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {      
            assertConstClaim(pool1, address(loan),  address(dlFactory1), IERC20(USDC), CONST_POOL_VALUE);
            assertConstClaim(pool1, address(loan),  address(dlFactory2), IERC20(USDC), CONST_POOL_VALUE);
            assertConstClaim(pool1, address(loan2), address(dlFactory1), IERC20(USDC), CONST_POOL_VALUE);
            assertConstClaim(pool1, address(loan2), address(dlFactory2), IERC20(USDC), CONST_POOL_VALUE);
        }
        
        assertTrue(pool1.principalOut() < 10);
    }

    function test_claim_singleLP() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            sid.approve(address(bPool), pool1.stakeLocker(), MAX_UINT);
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

            sid.finalize(address(pool1));
            sid.setOpenToPublic(address(pool1), true);
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("USDC", address(bob), 1_000_000_000 * USD);
            mint("USDC", address(che), 1_000_000_000 * USD);
            mint("USDC", address(dan), 1_000_000_000 * USD);

            bob.approve(USDC, address(pool1), MAX_UINT);
            che.approve(USDC, address(pool1), MAX_UINT);
            dan.approve(USDC, address(pool1), MAX_UINT);

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 * USD));  // 10%
            assertTrue(che.try_deposit(address(pool1), 300_000_000 * USD));  // 30%
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 * USD));  // 60%

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 200_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 200_000_000 * USD));

            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory1),  50_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory1),  50_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 150_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 150_000_000 * USD));
        }

        assertEq(pool1.principalOut(), 1_000_000_000 * USD);
        assertEq(IERC20(USDC).balanceOf(pool1.liquidityLocker()), 0);

        DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));  // debtLocker1 = DebtLocker 1, for loan using dlFactory1
        DebtLocker debtLocker2 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2 = DebtLocker 2, for loan using dlFactory2
        DebtLocker debtLocker3 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory1)));  // debtLocker3 = DebtLocker 3, for loan2 using dlFactory1
        DebtLocker debtLocker4 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4 = DebtLocker 4, for loan2 using dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(loan),  cReq1);
            fay.approve(WETH, address(loan2), cReq2);
            eli.drawdown(address(loan),  100_000_000 * USD);
            fay.drawdown(address(loan2), 100_000_000 * USD);
        }
        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        {
            (uint amt1_1,,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            (uint amt1_2,,,,) = loan2.getNextPayment(); // USDC required for 1st payment on loan2
            mint("USDC", address(eli), amt1_1);
            mint("USDC", address(fay), amt1_2);
            eli.approve(USDC, address(loan),  amt1_1);
            fay.approve(USDC, address(loan2), amt1_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {      
            checkClaim(debtLocker1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        {
            (uint amt2_1,,,,) =  loan.getNextPayment(); // USDC required for 2nd payment on loan
            (uint amt2_2,,,,) = loan2.getNextPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amt2_1);
            mint("USDC", address(fay), amt2_2);
            eli.approve(USDC, address(loan),  amt2_1);
            fay.approve(USDC, address(loan2), amt2_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));

            (uint amt3_1,,,,) =  loan.getNextPayment(); // USDC required for 3rd payment on loan
            (uint amt3_2,,,,) = loan2.getNextPayment(); // USDC required for 3rd payment on loan2
            mint("USDC", address(eli), amt3_1);
            mint("USDC", address(fay), amt3_2);
            eli.approve(USDC, address(loan),  amt3_1);
            fay.approve(USDC, address(loan2), amt3_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {      
            checkClaim(debtLocker1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // USDC required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amtf_1);
            mint("USDC", address(fay), amtf_2);
            eli.approve(USDC, address(loan),  amtf_1);
            fay.approve(USDC, address(loan2), amtf_2);
            eli.makeFullPayment(address(loan));
            fay.makeFullPayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {      
            checkClaim(debtLocker1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }

        assertTrue(pool1.principalOut() < 10);
    }
    
    function test_claim_multipleLP() public {

        /******************************************/
        /*** Stake & Finalize 2 Liquidity Pools ***/
        /******************************************/
        address stakeLocker1 = pool1.stakeLocker();
        address stakeLocker2 = pool2.stakeLocker();
        {
            sid.approve(address(bPool), stakeLocker1, MAX_UINT);
            joe.approve(address(bPool), stakeLocker2, MAX_UINT);
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);
            joe.stake(pool2.stakeLocker(), bPool.balanceOf(address(joe)) / 2);
            sid.finalize(address(pool1));
            sid.setOpenToPublic(address(pool1), true);
            joe.finalize(address(pool2));
            joe.setOpenToPublic(address(pool2), true);
        }
       
        address liqLocker1 = pool1.liquidityLocker();
        address liqLocker2 = pool2.liquidityLocker();

        /*************************************************************/
        /*** Mint and deposit funds into liquidity pools (1b each) ***/
        /*************************************************************/
        {
            mint("USDC", address(bob), 1_000_000_000 * USD);
            mint("USDC", address(che), 1_000_000_000 * USD);
            mint("USDC", address(dan), 1_000_000_000 * USD);

            bob.approve(USDC, address(pool1), MAX_UINT);
            che.approve(USDC, address(pool1), MAX_UINT);
            dan.approve(USDC, address(pool1), MAX_UINT);

            bob.approve(USDC, address(pool2), MAX_UINT);
            che.approve(USDC, address(pool2), MAX_UINT);
            dan.approve(USDC, address(pool2), MAX_UINT);

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 * USD));  // 10% BOB in LP1
            assertTrue(che.try_deposit(address(pool1), 300_000_000 * USD));  // 30% CHE in LP1
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 * USD));  // 60% DAN in LP1

            assertTrue(bob.try_deposit(address(pool2), 500_000_000 * USD));  // 50% BOB in LP2
            assertTrue(che.try_deposit(address(pool2), 400_000_000 * USD));  // 40% BOB in LP2
            assertTrue(dan.try_deposit(address(pool2), 100_000_000 * USD));  // 10% BOB in LP2

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }
        
        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

        /***************************/
        /*** Fund loan / loan2 ***/
        /***************************/
        {
            // LP 1 Vault 1
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 25_000_000 * USD));  // Fund loan using dlFactory1 for 25m USDC
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 25_000_000 * USD));  // Fund loan using dlFactory1 for 25m USDC, again, 50m USDC total
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 25_000_000 * USD));  // Fund loan using dlFactory2 for 25m USDC
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 25_000_000 * USD));  // Fund loan using dlFactory2 for 25m USDC (no excess), 100m USDC total

            // LP 2 Vault 1
            assertTrue(joe.try_fundLoan(address(pool2), address(loan),  address(dlFactory1), 50_000_000 * USD));  // Fund loan using dlFactory1 for 50m USDC (excess), 150m USDC total
            assertTrue(joe.try_fundLoan(address(pool2), address(loan),  address(dlFactory2), 50_000_000 * USD));  // Fund loan using dlFactory2 for 50m USDC (excess), 200m USDC total

            // LP 1 Vault 2
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory1), 50_000_000 * USD));  // Fund loan2 using dlFactory1 for 50m USDC
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory1), 50_000_000 * USD));  // Fund loan2 using dlFactory1 for 50m USDC, again, 100m USDC total
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory2), 50_000_000 * USD));  // Fund loan2 using dlFactory2 for 50m USDC
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory2), 50_000_000 * USD));  // Fund loan2 using dlFactory2 for 50m USDC again, 200m USDC total

            // LP 2 Vault 2
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory1), 100_000_000 * USD));  // Fund loan2 using dlFactory1 for 100m USDC
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory1), 100_000_000 * USD));  // Fund loan2 using dlFactory1 for 100m USDC, again, 400m USDC total
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory2), 100_000_000 * USD));  // Fund loan2 using dlFactory2 for 100m USDC (excess)
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory2), 100_000_000 * USD));  // Fund loan2 using dlFactory2 for 100m USDC (excess), 600m USDC total
        }
        
        DebtLocker debtLocker1_pool1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));  // debtLocker1_pool1 = DebtLocker 1, for pool1, for loan using dlFactory1
        DebtLocker debtLocker2_pool1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2_pool1 = DebtLocker 2, for pool1, for loan using dlFactory2
        DebtLocker debtLocker3_pool1 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory1)));  // debtLocker3_pool1 = DebtLocker 3, for pool1, for loan2 using dlFactory1
        DebtLocker debtLocker4_pool1 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4_pool1 = DebtLocker 4, for pool1, for loan2 using dlFactory2
        DebtLocker debtLocker1_pool2 = DebtLocker(pool2.debtLockers(address(loan),  address(dlFactory1)));  // debtLocker1_pool2 = DebtLocker 1, for pool2, for loan using dlFactory1
        DebtLocker debtLocker2_pool2 = DebtLocker(pool2.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2_pool2 = DebtLocker 2, for pool2, for loan using dlFactory2
        DebtLocker debtLocker3_pool2 = DebtLocker(pool2.debtLockers(address(loan2), address(dlFactory1)));  // debtLocker3_pool2 = DebtLocker 3, for pool2, for loan2 using dlFactory1
        DebtLocker debtLocker4_pool2 = DebtLocker(pool2.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4_pool2 = DebtLocker 4, for pool2, for loan2 using dlFactory2

        // Present state checks
        assertEq(IERC20(USDC).balanceOf(liqLocker1),              700_000_000 * USD);  // 1b USDC deposited - (100m USDC - 200m USDC)
        assertEq(IERC20(USDC).balanceOf(liqLocker2),              500_000_000 * USD);  // 1b USDC deposited - (100m USDC - 400m USDC)
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),  200_000_000 * USD);  // Balance of loan fl 
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker2)), 600_000_000 * USD);  // Balance of loan2 fl (no excess, exactly 400 USDC from LP1 & 600 USDC from LP2)
        assertEq(loan.balanceOf(address(debtLocker1_pool1)),       50_000_000 ether);  // Balance of debtLocker1 for pool1 with dlFactory1
        assertEq(loan.balanceOf(address(debtLocker2_pool1)),       50_000_000 ether);  // Balance of debtLocker2 for pool1 with dlFactory2
        assertEq(loan2.balanceOf(address(debtLocker3_pool1)),     100_000_000 ether);  // Balance of debtLocker3 for pool1 with dlFactory1
        assertEq(loan2.balanceOf(address(debtLocker4_pool1)),     100_000_000 ether);  // Balance of debtLocker4 for pool1 with dlFactory2
        assertEq(loan.balanceOf(address(debtLocker1_pool2)),       50_000_000 ether);  // Balance of debtLocker1 for pool2 with dlFactory1
        assertEq(loan.balanceOf(address(debtLocker2_pool2)),       50_000_000 ether);  // Balance of debtLocker2 for pool2 with dlFactory2
        assertEq(loan2.balanceOf(address(debtLocker3_pool2)),     200_000_000 ether);  // Balance of debtLocker3 for pool2 with dlFactory1
        assertEq(loan2.balanceOf(address(debtLocker4_pool2)),     200_000_000 ether);  // Balance of debtLocker4 for pool2 with dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(500_000_000 * USD); // wETH required for 500m USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(400_000_000 * USD); // wETH required for 500m USDC drawdown on loan2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(loan),  cReq1);
            fay.approve(WETH, address(loan2), cReq2);
            eli.drawdown(address(loan),  100_000_000 * USD); // 100m excess to be returned
            fay.drawdown(address(loan2), 300_000_000 * USD); // 200m excess to be returned
        }

        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        {
            (uint amt1_1,,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            (uint amt1_2,,,,) = loan2.getNextPayment(); // USDC required for 1st payment on loan2
            mint("USDC", address(eli), amt1_1);
            mint("USDC", address(fay), amt1_2);
            eli.approve(USDC, address(loan),  amt1_1);
            fay.approve(USDC, address(loan2), amt1_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /*******************/
        /***  Pool Claim ***/
        /*******************/
        {
            checkClaim(debtLocker1_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker2_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker4_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        {
            (uint amt2_1,,,,) =  loan.getNextPayment(); // USDC required for 2nd payment on loan
            (uint amt2_2,,,,) = loan2.getNextPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amt2_1);
            mint("USDC", address(fay), amt2_2);
            eli.approve(USDC, address(loan),  amt2_1);
            fay.approve(USDC, address(loan2), amt2_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));

            (uint amt3_1,,,,) =  loan.getNextPayment(); // USDC required for 3rd payment on loan
            (uint amt3_2,,,,) = loan2.getNextPayment(); // USDC required for 3rd payment on loan2
            mint("USDC", address(eli), amt3_1);
            mint("USDC", address(fay), amt3_2);
            eli.approve(USDC, address(loan),  amt3_1);
            fay.approve(USDC, address(loan2), amt3_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }

        /*******************/
        /***  Pool Claim ***/
        /*******************/
        {
            checkClaim(debtLocker1_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker2_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker4_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // USDC required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amtf_1);
            mint("USDC", address(fay), amtf_2);
            eli.approve(USDC, address(loan),  amtf_1);
            fay.approve(USDC, address(loan2), amtf_2);
            eli.makeFullPayment(address(loan));
            fay.makeFullPayment(address(loan2));
        }
        
        /*******************/
        /***  Pool Claim ***/
        /*******************/
        {
            checkClaim(debtLocker1_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker2_pool1, loan,  sid, IERC20(USDC), pool1, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory1));
            checkClaim(debtLocker4_pool1, loan2, sid, IERC20(USDC), pool1, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker2_pool2, loan,  joe, IERC20(USDC), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory1));
            checkClaim(debtLocker4_pool2, loan2, joe, IERC20(USDC), pool2, address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }

        assertTrue(pool1.principalOut() < 10);
        assertTrue(pool2.principalOut() < 10);
    }

    function test_claim_external_transfers() public {
        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            sid.approve(address(bPool), pool1.stakeLocker(), uint(-1));
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

            sid.finalize(address(pool1));
            sid.setOpenToPublic(address(pool1), true);
            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        /**********************************************************/
        /*** Mint, deposit funds into liquidity pool, fund loan ***/
        /**********************************************************/
        {
            mint("USDC", address(bob), 1_000_000_000 * USD);
            bob.approve(USDC, address(pool1), uint(-1));
            bob.approve(USDC, address(this),  uint(-1));
            bob.deposit(address(pool1), 100_000_000 * USD);
            sid.fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 * USD);
            assertTrue(pool1.debtLockers(address(loan), address(dlFactory1)) != address(0));
            assertEq(pool1.principalOut(), 100_000_000 * USD);
        }

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            mint("WETH", address(eli), cReq1);
            eli.approve(WETH, address(loan),  cReq1);
            eli.drawdown(address(loan),  100_000_000 * USD);
        }

        /*****************************/
        /*** Make Interest Payment ***/
        /*****************************/
        {
            (uint amt,,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            mint("USDC", address(eli), amt);
            eli.approve(USDC, address(loan),  amt);
            eli.makePayment(address(loan));
        }

        /****************************************************/
        /*** Transfer USDC into Pool, Loan and debtLocker ***/
        /****************************************************/
        {
            DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));

            uint256 poolBal_before       = IERC20(USDC).balanceOf(address(pool1));
            uint256 debtLockerBal_before = IERC20(USDC).balanceOf(address(debtLocker1));

            IERC20(USDC).transferFrom(address(bob), address(pool1),       1000 * USD);
            IERC20(USDC).transferFrom(address(bob), address(debtLocker1), 2000 * USD);
            IERC20(USDC).transferFrom(address(bob), address(loan),        2000 * USD);

            uint256 poolBal_after       = IERC20(USDC).balanceOf(address(pool1));
            uint256 debtLockerBal_after = IERC20(USDC).balanceOf(address(debtLocker1));

            assertEq(poolBal_after - poolBal_before,             1000 * USD);
            assertEq(debtLockerBal_after - debtLockerBal_before, 2000 * USD);

            poolBal_before       = poolBal_after;
            debtLockerBal_before = debtLockerBal_after;

            checkClaim(debtLocker1, loan, sid, IERC20(USDC), pool1, address(dlFactory1));

            poolBal_after       = IERC20(USDC).balanceOf(address(pool1));
            debtLockerBal_after = IERC20(USDC).balanceOf(address(debtLocker1));

            assertTrue(poolBal_after - poolBal_before < 10);  // Collects some rounding dust
            assertEq(debtLockerBal_after, debtLockerBal_before);
        }

        /*************************/
        /*** Make Full Payment ***/
        /*************************/
        {
            (uint amt,,) =  loan.getFullPayment(); // USDC required for 1st payment on loan
            mint("USDC", address(eli), amt);
            eli.approve(USDC, address(loan),  amt);
            eli.makeFullPayment(address(loan));
        }

        /*********************************************************/
        /*** Check claim with existing balances in DL and Pool ***/
        /*** Transfer more funds into Loan                     ***/
        /*********************************************************/
        {
            DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));

            // Transfer funds into Loan to make principalClaim > principalOut
            ERC20(USDC).transferFrom(address(bob), address(loan), 200000 * USD);

            uint256 poolBal_before       = IERC20(USDC).balanceOf(address(pool1));
            uint256 debtLockerBal_before = IERC20(USDC).balanceOf(address(debtLocker1));

            checkClaim(debtLocker1, loan, sid, IERC20(USDC), pool1, address(dlFactory1));

            uint256 poolBal_after       = IERC20(USDC).balanceOf(address(pool1));
            uint256 debtLockerBal_after = IERC20(USDC).balanceOf(address(debtLocker1));

            assertTrue(poolBal_after - poolBal_before < 10);  // Collects some rounding dust
            assertEq(debtLockerBal_after, debtLockerBal_before);
        }

        assertTrue(pool1.principalOut() < 10);
    }

    function setUpWithdraw() internal {
        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            sid.approve(address(bPool), pool1.stakeLocker(), MAX_UINT);
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);
            sid.setOpenToPublic(address(pool1), true);
            sid.finalize(address(pool1));
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("USDC", address(bob), 1_000_000_000 * USD);
            mint("USDC", address(che), 1_000_000_000 * USD);
            mint("USDC", address(dan), 1_000_000_000 * USD);

            bob.approve(USDC, address(pool1), MAX_UINT);
            che.approve(USDC, address(pool1), MAX_UINT);
            dan.approve(USDC, address(pool1), MAX_UINT);

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 * USD));  // 10%
            assertTrue(che.try_deposit(address(pool1), 300_000_000 * USD));  // 30%
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 * USD));  // 60%

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 200_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 200_000_000 * USD));

            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory1),  50_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory1),  50_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 150_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 150_000_000 * USD));
        }

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(100_000_000 * USD); // wETH required for 100_000_000 USDC drawdown on loan2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(loan),  cReq1);
            fay.approve(WETH, address(loan2), cReq2);
            eli.drawdown(address(loan),  100_000_000 * USD);
            fay.drawdown(address(loan2), 100_000_000 * USD);
        }
        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        {
            (uint amt1_1,,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            (uint amt1_2,,,,) = loan2.getNextPayment(); // USDC required for 1st payment on loan2
            mint("USDC", address(eli), amt1_1);
            mint("USDC", address(fay), amt1_2);
            eli.approve(USDC, address(loan),  amt1_1);
            fay.approve(USDC, address(loan2), amt1_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {   
            sid.claim(address(pool1), address(loan),  address(dlFactory1));
            sid.claim(address(pool1), address(loan),  address(dlFactory2));
            sid.claim(address(pool1), address(loan2), address(dlFactory1));
            sid.claim(address(pool1), address(loan2), address(dlFactory2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        {
            (uint amt2_1,,,,) =  loan.getNextPayment(); // USDC required for 2nd payment on loan
            (uint amt2_2,,,,) = loan2.getNextPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amt2_1);
            mint("USDC", address(fay), amt2_2);
            eli.approve(USDC, address(loan),  amt2_1);
            fay.approve(USDC, address(loan2), amt2_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));

            (uint amt3_1,,,,) =  loan.getNextPayment(); // USDC required for 3rd payment on loan
            (uint amt3_2,,,,) = loan2.getNextPayment(); // USDC required for 3rd payment on loan2
            mint("USDC", address(eli), amt3_1);
            mint("USDC", address(fay), amt3_2);
            eli.approve(USDC, address(loan),  amt3_1);
            fay.approve(USDC, address(loan2), amt3_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {      
            sid.claim(address(pool1), address(loan),  address(dlFactory1));
            sid.claim(address(pool1), address(loan),  address(dlFactory2));
            sid.claim(address(pool1), address(loan2), address(dlFactory1));
            sid.claim(address(pool1), address(loan2), address(dlFactory2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // USDC required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amtf_1);
            mint("USDC", address(fay), amtf_2);
            eli.approve(USDC, address(loan),  amtf_1);
            fay.approve(USDC, address(loan2), amtf_2);
            eli.makeFullPayment(address(loan));
            fay.makeFullPayment(address(loan2));
        }
        
        /******************/
        /*** Pool Claim ***/
        /******************/
        {   
            sid.claim(address(pool1), address(loan),  address(dlFactory1));
            sid.claim(address(pool1), address(loan),  address(dlFactory2));
            sid.claim(address(pool1), address(loan2), address(dlFactory1));
            sid.claim(address(pool1), address(loan2), address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }
    }
    
    function test_withdraw_calculator() public {

        setUpWithdraw();

        uint256 start = block.timestamp;
        uint256 delay = pool1.penaltyDelay();

        assertEq(pool1.calcWithdrawPenalty(1 * USD, address(bob)), uint256(0));  // Returns 0 when lockupPeriod > penaltyDelay.
        assertTrue(!joe.try_setLockupPeriod(address(pool1), 15 days));
        assertEq(pool1.lockupPeriod(), 180 days);
        assertTrue(sid.try_setLockupPeriod(address(pool1), 15 days));
        assertEq(pool1.lockupPeriod(), 15 days);

        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 1 ether);  // 100% of (interest + penalty) is subtracted on immediate withdrawal

        hevm.warp(start + delay / 3);
        withinPrecision(pool1.calcWithdrawPenalty(1 ether, address(bob)), uint(2 ether) / 3, 6); // After 1/3 delay has passed, 2/3 (interest + penalty) is subtracted

        hevm.warp(start + delay / 2);
        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 0.5 ether);  // After half delay has passed, 1/2 (interest + penalty) is subtracted

        hevm.warp(start + delay - 1);
        assertTrue(pool1.calcWithdrawPenalty(1 ether, address(bob)) > 0); // Still a penalty
        
        hevm.warp(start + delay);
        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 0); // After delay has passed, no penalty

        hevm.warp(start + delay + 1);
        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 0); 

        hevm.warp(start + delay * 2);
        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 0);

        hevm.warp(start + delay * 1000);
        assertEq(pool1.calcWithdrawPenalty(1 ether, address(bob)), 0);
    }

    function test_withdraw_under_lockup_period() public {
        setUpWithdraw();
        uint start = block.timestamp;

        // Mint USDC to kim
        mint("USDC", address(kim), 5000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));
        
        // Deposit 1000 USDC and check depositDate
        assertTrue(kim.try_deposit(address(pool1), 1000 * USD));
        assertEq(pool1.depositDate(address(kim)), start);

        // Fund loan, drawdown, make payment and claim so kim can claim interest
        assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1000 * USD), "Fail to fund the loan");
        _drawDownLoan(1000 * USD, loan3, hal);
        _makeLoanPayment(loan3, hal); 
        sid.claim(address(pool1), address(loan3), address(dlFactory1));
        assertEq(pool1.calcWithdrawPenalty(1000 * USD, address(kim)), uint256(0)); // lockupPeriod > withdrawDelay

        uint256 interest = pool1.withdrawableFundsOf(address(kim));  // Get kims withdrawable funds

        assertTrue(kim.try_intendToWithdraw(address(pool1)));
        // Warp to exact time that kim can withdraw with weighted deposit date
        hevm.warp(pool1.depositDate(address(kim)) + pool1.lockupPeriod() - 1);
        assertTrue(!kim.try_withdraw(address(pool1), 1000 * USD), "Withdraw failure didn't trigger");
        hevm.warp(pool1.depositDate(address(kim)) + pool1.lockupPeriod());
        assertTrue( kim.try_withdraw(address(pool1), 1000 * USD), "Failed to withdraw funds");

        assertEq(IERC20(USDC).balanceOf(address(kim)) - bal0, interest);
    }

    function test_withdraw_under_weighted_lockup_period() public {
        setUpWithdraw();
        uint start = block.timestamp;

        // Mint USDC to kim
        mint("USDC", address(kim), 5000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));

        // Deposit 1000 USDC and check depositDate
        assertTrue(kim.try_deposit(address(pool1), 1000 * USD));
        assertEq(pool1.depositDate(address(kim)), start);

        // Fund loan, drawdown, make payment and claim so kim can claim interest
        assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1000 * USD), "Fail to fund the loan");
        _drawDownLoan(1000 * USD, loan3, hal);
        _makeLoanPayment(loan3, hal); 
        sid.claim(address(pool1), address(loan3), address(dlFactory1));
        assertEq(pool1.calcWithdrawPenalty(1000 * USD, address(kim)), uint256(0)); // lockupPeriod > withdrawDelay

        // Warp to exact time that kim can withdraw for the first time
        hevm.warp(start + pool1.lockupPeriod());  
        assertEq(block.timestamp - pool1.depositDate(address(kim)), pool1.lockupPeriod());  // Can withdraw at this point
        
        // Deposit more USDC into pool, increasing deposit date and locking up funds again
        assertTrue(kim.try_deposit(address(pool1), 3000 * USD));
        assertEq(pool1.depositDate(address(kim)) - start, (block.timestamp - start) * (3000 * WAD) / (4000 * WAD));  // Deposit date updating using weighting
        assertTrue( kim.try_intendToWithdraw(address(pool1)));
        assertTrue(!kim.try_withdraw(address(pool1), 4000 * USD), "Withdraw failure didn't trigger");                // Not able to withdraw the funds as deposit date was updated

        uint256 interest = pool1.withdrawableFundsOf(address(kim));  // Get kims withdrawable funds

        // Warp to exact time that kim can withdraw with weighted deposit date
        hevm.warp(pool1.depositDate(address(kim)) + pool1.lockupPeriod() - 1);
        assertTrue(!kim.try_withdraw(address(pool1), 4000 * USD), "Withdraw failure didn't trigger");
        hevm.warp(pool1.depositDate(address(kim)) + pool1.lockupPeriod());
        assertTrue( kim.try_withdraw(address(pool1), 4000 * USD), "Failed to withdraw funds");

        assertEq(IERC20(USDC).balanceOf(address(kim)) - bal0, interest);
    }

    function test_withdraw_no_principal_penalty() public {
        setUpWithdraw();
        
        uint start = block.timestamp;

        sid.setPrincipalPenalty(address(pool1), 0);
        assertTrue(sid.try_setLockupPeriod(address(pool1), 0));
        assertEq(pool1.lockupPeriod(), uint256(0));

        mint("USDC", address(kim), 2000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        assertTrue(kim.try_deposit(address(pool1), 1000 * USD));
        
        (uint total_kim, uint principal_kim, uint interest_kim) = pool1.claimableFunds(address(kim));

        assertEq(total_kim,     1000 * USD);
        assertEq(principal_kim, 1000 * USD);
        assertEq(interest_kim,           0);

        uint256 withdrawAmount = 1000 * USD;
        make_withdrawable(kim, pool1);
        kim.withdraw(address(pool1), withdrawAmount);

        assertEq(IERC20(USDC).balanceOf(address(kim)), 2000 * USD);
        
        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));

        assertTrue(kim.try_deposit(address(pool1), 1000 * USD), "Fail to deposit liquidity");                                      // Add another 1000 USDC.
        assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1000 * USD), "Fail to fund the loan");   // Fund the loan.
        hevm.warp(start + pool1.penaltyDelay());                                                                                   // Fast-forward to claim all proportionate interest.
        _drawDownLoan(1000 * USD, loan3, hal);                                                                                     // Draw down the loan.
        _makeLoanPayment(loan3, hal);                                                                                              // Make loan payment.
        sid.claim(address(pool1), address(loan3), address(dlFactory1));                                                            // Fund claimed by the pool.

        uint256 interest = pool1.withdrawableFundsOf(address(kim));

        make_withdrawable(kim, pool1);
        kim.withdraw(address(pool1), withdrawAmount);
        uint256 bal1 = IERC20(USDC).balanceOf(address(kim));

        assertEq(bal1 - bal0, interest);
    }

    function test_withdraw_principal_penalty() public {
        setUpWithdraw();
        
        sid.setPrincipalPenalty(address(pool1), 500);
        assertTrue(sid.try_setLockupPeriod(address(pool1), 0));
        assertEq(pool1.lockupPeriod(), uint256(0));

        mint("USDC", address(kim), 2000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);

        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));
        uint256 depositAmount = 1000 * USD;
        assertTrue(kim.try_deposit(address(pool1), depositAmount));  // Deposit and withdraw in same tx
        make_withdrawable(kim, pool1);

        (uint total_kim, uint principal_kim, uint interest_kim) = pool1.claimableFunds(address(kim));

        withinPrecision(total_kim,     966 * USD, 3);
        withinPrecision(principal_kim, 966 * USD, 3);
        assertEq(interest_kim,          0);

        kim.withdraw(address(pool1), depositAmount);
        uint256 bal1 = IERC20(USDC).balanceOf(address(kim));  // Balance after principal penalty

        withinPrecision(bal0 - bal1, 33 * USD, 2); // 3% principal penalty.
    }

    function test_withdraw_principal_and_interest_penalty() public {
        setUpWithdraw();

        uint start = block.timestamp;
        
        sid.setPrincipalPenalty(address(pool1), 500);
        assertTrue(sid.try_setLockupPeriod(address(pool1), 0));
        assertEq(pool1.lockupPeriod(), uint256(0));

        mint("USDC", address(kim), 2000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        
        // Do another deposit with same amount
        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));  // Get balance before deposit
        uint256 depositAmount = 1000 * USD;
        uint256 lpToken       = 1000 * WAD;
        uint256 beforeTotalSupply = pool1.totalSupply();

        {
            uint256 beforeLLBalance = IERC20(USDC).balanceOf(pool1.liquidityLocker());

            assertTrue(kim.try_deposit(address(pool1),  depositAmount));  // Add another 1000 USDC.
            assertTrue(kim.try_intendToWithdraw(address(pool1)));                                                           
            assertEq(pool1.balanceOf(address(kim)),     lpToken, "Failed to update LP balance");                                   // Verify the LP token balance.
            assertEq(pool1.totalSupply(),               beforeTotalSupply.add(lpToken), "Failed to update the TS");                // Pool total supply get increase by the lpToken.
            assertEq(_getLLBal(pool1),                  beforeLLBalance.add(depositAmount), "Failed to update the LL balance");    // Make sure liquidity locker balance get increases.

            assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1000 * USD), "Fail to fund the loan");  // Fund the loan.
            assertEq(_getLLBal(pool1),                  beforeLLBalance, "Failed to update the LL balance");                          // Make sure liquidity locker balance get increases.

            _drawDownLoan(1000 * USD, loan3, hal);                             // Draw down the loan.
            hevm.warp(start + pool1.penaltyDelay() - 10 days);                 // Fast-forward to claim all proportionate interest, taking a penalty
            _makeLoanPayment(loan3, hal);                                      // Make loan payment.
            sid.claim(address(pool1), address(loan3), address(dlFactory1));    // Fund claimed by the pool
        }

        {
            uint256 interest       = pool1.withdrawableFundsOf(address(kim));
            uint256 priPenalty     = pool1.principalPenalty().mul(depositAmount).div(10000);             // Calculate flat principal penalty.
            uint256 totPenalty     = pool1.calcWithdrawPenalty(interest.add(priPenalty), address(kim));  // Get total penalty
            uint256 oldInterestSum = pool1.interestSum();
            
            (uint256 total_kim,,) = pool1.claimableFunds(address(kim));
            uint256 bal1 = IERC20(USDC).balanceOf(address(kim));  // Get balance before withdraw

            kim.withdraw(address(pool1), depositAmount);

            uint256 bal2 = IERC20(USDC).balanceOf(address(kim));                                          // Get balance after withdraw
            uint256 balanceDiff = bal2 > bal0 ? bal2 - bal0 : bal0 - bal2;                                // Get balance difference between before deposit and after withdraw
            uint256 extraAmount = totPenalty > interest ? totPenalty - interest : interest - totPenalty;  // Get amount from interest/pentalty

            assertEq(total_kim, bal2 - bal1);
            assertTrue(totPenalty != uint256(0));
            withinPrecision(balanceDiff, extraAmount, 6);                                                                        // All of principal returned, plus interest
            assertEq(pool1.balanceOf(address(kim)),                 0,                    "Failed to burn the tokens");          // LP tokens get burned.
            assertEq(pool1.totalSupply(),                           beforeTotalSupply,    "Failed to decrement the supply");     // Supply get reset.
            assertEq(oldInterestSum.sub(interest).add(totPenalty),  pool1.interestSum(),  "Failed to update the interest sum");  // Interest sum is increased by totPenalty and decreased by the entitled interest.
        }
    }

    function test_withdraw_protocol_paused() public {
        setUpWithdraw();
        
        sid.setPrincipalPenalty(address(pool1), 0);
        assertTrue(sid.try_setLockupPeriod(address(pool1), 0));
        assertEq(pool1.lockupPeriod(), uint256(0));

        mint("USDC", address(kim), 2000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        assertTrue(kim.try_deposit(address(pool1), 1000 * USD));
        make_withdrawable(kim, pool1);

        // Protocol-wide pause by Emergency Admin
        assertTrue(!globals.protocolPaused());
        assertTrue(mic.try_setProtocolPause(address(globals), true));

        // Attempt to withdraw while protocol paused
        assertTrue(globals.protocolPaused());
        assertTrue(!kim.try_withdrawFunds(address(pool1)));
        assertTrue(!kim.try_withdraw(address(pool1), 1000 * USD));

        // Unpause and withdraw
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(kim.try_withdrawFunds(address(pool1)));
        assertTrue(kim.try_withdraw(address(pool1), 1000 * USD));

        assertEq(IERC20(USDC).balanceOf(address(kim)), 2000 * USD);
    }

    function test_setPenaltyDelay() public {
        assertEq(pool1.penaltyDelay(), 30 days);
        assertTrue(!joe.try_setPenaltyDelay(address(pool1), 45 days));
        
        // Pause protocol and attempt setPenaltyDelay()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_setPenaltyDelay(address(pool1), 45 days));
        assertEq(pool1.penaltyDelay(), 30 days);

        // Unpause protocol and setPenaltyDelay()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_setPenaltyDelay(address(pool1), 45 days));
        assertEq(pool1.penaltyDelay(), 45 days);
        
    }

    function test_setPrincipalPenalty() public {
        assertEq(pool1.principalPenalty(), 500);
        assertTrue(!joe.try_setPrincipalPenalty(address(pool1), 1125));

        // Pause protocol and attempt setPrincipalPenalty()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_setPrincipalPenalty(address(pool1), 1125));
        assertEq(pool1.principalPenalty(), 500);

        // Unpause protocol and setPrincipalPenalty()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_setPrincipalPenalty(address(pool1), 1125));
        assertEq(pool1.principalPenalty(), 1125);
    }

    function _makeLoanPayment(Loan _loan, Borrower by) internal {
        (uint amt,,,,) = _loan.getNextPayment();
        mint("USDC", address(by), amt);
        by.approve(USDC, address(_loan),  amt);
        by.makePayment(address(_loan));
    }

    function _drawDownLoan(uint256 drawdownAmount, Loan _loan, Borrower by) internal  {
        uint cReq =  _loan.collateralRequiredForDrawdown(drawdownAmount);
        mint("WETH", address(by), cReq);
        by.approve(WETH, address(_loan),  cReq);
        by.drawdown(address(_loan),  drawdownAmount);
    }

    function _getLLBal(Pool who) internal view returns(uint256) {
        return IERC20(USDC).balanceOf(who.liquidityLocker());
    }

    function test_deactivate() public {

        setUpWithdraw();

        address liquidityAsset = address(pool1.liquidityAsset());
        uint liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool1.principalOut() <= 100 * 10 ** liquidityAssetDecimals);

        // Pause protocol and attempt deactivate()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_deactivate(address(pool1)));

        // Unpause protocol and deactivate()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_deactivate(address(pool1)));

        // Post-state checks.
        assertEq(int(pool1.poolState()), 2);

        // Deactivation should block the following functionality:

        // deposit()
        mint("USDC", address(bob), 1_000_000_000 * USD);
        bob.approve(USDC, address(pool1), uint(-1));
        assertTrue(!bob.try_deposit(address(pool1), 100_000_000 * USD));

        // fundLoan()
        assertTrue(!sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 1));

        // deactivate()
        assertTrue(!sid.try_deactivate(address(pool1)));

    }

    function test_deactivate_fail() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            sid.approve(address(bPool), pool1.stakeLocker(), MAX_UINT);
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);
            sid.setOpenToPublic(address(pool1), true);
            sid.finalize(address(pool1));
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("USDC", address(bob), 1_000_000_000 * USD);
            mint("USDC", address(che), 1_000_000_000 * USD);
            mint("USDC", address(dan), 1_000_000_000 * USD);

            bob.approve(USDC, address(pool1), MAX_UINT);
            che.approve(USDC, address(pool1), MAX_UINT);
            dan.approve(USDC, address(pool1), MAX_UINT);

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 * USD));  // 10%
            assertTrue(che.try_deposit(address(pool1), 300_000_000 * USD));  // 30%
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 * USD));  // 60%

            gov.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 200_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 200_000_000 * USD));

            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory1),  50_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory1),  50_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 150_000_000 * USD));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 150_000_000 * USD));
        }

        address liquidityAsset = address(pool1.liquidityAsset());
        uint liquidityAssetDecimals = IERC20Details(liquidityAsset).decimals();

        // Pre-state checks.
        assertTrue(pool1.principalOut() >= 100 * 10 ** liquidityAssetDecimals);
        assertTrue(!sid.try_deactivate(address(pool1)));
    }

    function test_view_balance() public {
        setUpWithdraw();

        // Mint and deposit 1000 USDC
        mint("USDC", address(kim), 1_000_000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        assertTrue(kim.try_deposit(address(pool1), 1_000_000 * USD));

        // Fund loan, drawdown, make payment and claim so kim can claim interest
        assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1_000_000 * USD), "Fail to fund the loan");
        _drawDownLoan(1_000_000 * USD, loan3, hal);
        _makeLoanPayment(loan3, hal); 
        sid.claim(address(pool1), address(loan3), address(dlFactory1));

        uint withdrawDate = pool1.depositDate(address(kim)).add(pool1.lockupPeriod());

        hevm.warp(withdrawDate - 1);
        (uint total_kim, uint principal_kim, uint interest_kim) = pool1.claimableFunds(address(kim));

        // Deposit is still in lock-up
        assertEq(principal_kim, 0);
        assertEq(interest_kim, pool1.withdrawableFundsOf(address(kim)));
        assertEq(total_kim, principal_kim + interest_kim);

        hevm.warp(withdrawDate);
        (total_kim, principal_kim, interest_kim) = pool1.claimableFunds(address(kim));

        assertGt(principal_kim, 0);
        assertGt(interest_kim, 0);
        assertGt(total_kim, 0);
        assertEq(total_kim, principal_kim + interest_kim);

        uint256 kim_bal_pre = IERC20(pool1.liquidityAsset()).balanceOf(address(kim));
        
        make_withdrawable(kim, pool1);

        assertTrue(kim.try_withdraw(address(pool1), principal_kim), "Failed to withdraw claimable_kim");
        
        uint256 kim_bal_post = IERC20(pool1.liquidityAsset()).balanceOf(address(kim));

        assertEq(kim_bal_post - kim_bal_pre, principal_kim + interest_kim);
    }

    function test_reclaim_erc20() external {
        // Fund the pool with different kind of asset.
        mint("USDC", address(pool1), 1000 * USD);
        mint("DAI",  address(pool1), 1000 * WAD);
        mint("WETH", address(pool1),  100 * WAD);

        Governor fakeGov = new Governor();

        uint256 beforeBalanceDAI  = IERC20(DAI).balanceOf(address(gov));
        uint256 beforeBalanceWETH = IERC20(WETH).balanceOf(address(gov));

        assertTrue(!fakeGov.try_reclaimERC20(address(pool1), DAI));
        assertTrue(    !gov.try_reclaimERC20(address(pool1), USDC));
        assertTrue(    !gov.try_reclaimERC20(address(pool1), address(0)));
        assertTrue(     gov.try_reclaimERC20(address(pool1), DAI));
        assertTrue(     gov.try_reclaimERC20(address(pool1), WETH));

        uint256 afterBalanceDAI  = IERC20(DAI).balanceOf(address(gov));
        uint256 afterBalanceWETH = IERC20(WETH).balanceOf(address(gov));

        assertEq(afterBalanceDAI - beforeBalanceDAI,   1000 * WAD);
        assertEq(afterBalanceWETH - beforeBalanceWETH,  100 * WAD);
    }

    function test_setAllowList() public {
        // Pause protocol and attempt setAllowList()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_setAllowList(address(pool1), address(bob), true));
        assertTrue(!pool1.allowedLiquidityProviders(address(bob)));

        // Unpause protocol and setAllowList()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_setAllowList(address(pool1), address(bob), true));
        assertTrue(pool1.allowedLiquidityProviders(address(bob)));
    }

    function test_setAllowlistStakeLocker() public {
        // Pause protocol and attempt setAllowlistStakeLocker()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_setAllowlistStakeLocker(address(pool1), address(buf), true));
        assertTrue(!IStakeLocker(pool1.stakeLocker()).allowed(address(buf)));

        // Unpause protocol and setAllowlistStakeLocker()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_setAllowlistStakeLocker(address(pool1), address(buf), true));
        assertTrue(IStakeLocker(pool1.stakeLocker()).allowed(address(buf)));
    }

    function test_setAdmin() public {
        // Pause protocol and attempt setAdmin()
        assertTrue( mic.try_setProtocolPause(address(globals), true));
        assertTrue(!sid.try_setAdmin(address(pool1), address(pop), true));
        assertTrue(!pool1.admins(address(pop)));

        // Unpause protocol and setAdmin()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(sid.try_setAdmin(address(pool1), address(pop), true));
        assertTrue(pool1.admins(address(pop)));
    }

}
