// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/LP.sol";
import "./user/PoolDelegate.sol";
import "./user/Staker.sol";
import "./user/EmergencyAdmin.sol";

import "../interfaces/IBFactory.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IStakeLocker.sol";

import "../RepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../DebtLocker.sol";
import "../DebtLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LateFeeCalc.sol";
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

contract StakeLockerTest is TestUtil {

    using SafeMath for uint256;

    Borrower                               bob;
    Governor                               gov;
    LP                                     leo;
    PoolDelegate                           pat;
    PoolDelegate                           pam;
    Staker                                 sam;
    Staker                                 sid;
    Staker                                 sue;

    EmergencyAdmin              emergencyAdmin;

    RepaymentCalc                repaymentCalc;
    CollateralLockerFactory          clFactory;
    DebtLockerFactory                dlFactory;
    FundingLockerFactory             flFactory;
    LateFeeCalc                    lateFeeCalc;
    LiquidityLockerFactory           llFactory;
    Loan                                  loan;
    LoanFactory                    loanFactory;
    MapleGlobals                       globals;
    MapleToken                             mpl;
    Pool                                  pool;
    PremiumCalc                    premiumCalc;
    PoolFactory                    poolFactory;
    StakeLockerFactory               slFactory;
    Treasury                               trs;
    ChainlinkOracle                 wethOracle;
    ChainlinkOracle                 wbtcOracle;
    UsdOracle                        usdOracle;

    IBPool                               bPool;
    IStakeLocker                   stakeLocker;

    function setUp() public {

        bob            = new Borrower();                                                // Actor: Borrower of the Loan.
        gov            = new Governor();                                                // Actor: Governor of Maple.
        leo            = new LP();                                                      // Actor: Liquidity provider.
        pat            = new PoolDelegate();                                            // Actor: Manager of the Pool.
        pam            = new PoolDelegate();                                            // Actor: Manager of the Pool.
        sam            = new Staker();                                                  // Actor: Stakes BPTs in Pool.
        sid            = new Staker();                                                  // Actor: Stakes BPTs in Pool.
        sue            = new Staker();                                                  // Actor: Stakes BPTs in Pool.
        
        emergencyAdmin = new EmergencyAdmin();                                          // Actor: Emergency Admin of the protocol.

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl));
        flFactory      = new FundingLockerFactory();                                    // Setup the FL factory to facilitate Loan factory functionality.
        clFactory      = new CollateralLockerFactory();                                 // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory    = new LoanFactory(address(globals));                             // Create Loan factory.
        slFactory      = new StakeLockerFactory();                                      // Setup the SL factory to facilitate Pool factory functionality.
        llFactory      = new LiquidityLockerFactory();                                  // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory    = new PoolFactory(address(globals));                             // Create pool factory.
        dlFactory      = new DebtLockerFactory();                                       // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        repaymentCalc  = new RepaymentCalc();                                           // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                                            // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);                                          // Flat 5% premium
        trs            = new Treasury();                                                // Treasury.

        gov.setValidLoanFactory(address(loanFactory), true);
        gov.setValidPoolFactory(address(poolFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);

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

        bPool.bind(USDC, 50_000_000 * USD, 5 ether);       // Bind 50M USDC with 5 denormalization weight
        bPool.bind(address(mpl), 100_000 * WAD, 5 ether);  // Bind 100K MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * USD);
        assertEq(mpl.balanceOf(address(bPool)),             100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized

        gov.setPoolDelegateAllowlist(address(pat), true);
        gov.setMapleTreasury(address(trs));
        gov.setAdmin(address(emergencyAdmin));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(pat), 50 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(sam), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
        bPool.transfer(address(sid), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool

        gov.setValidBalancerPool(address(bPool), true);

        // Set Globals
        gov.setCalc(address(repaymentCalc), true);
        gov.setCalc(address(lateFeeCalc),   true);
        gov.setCalc(address(premiumCalc),   true);
        gov.setCollateralAsset(WETH,        true);
        gov.setLiquidityAsset(USDC,         true);
        gov.setSwapOutRequired(1_000_000);

        // Create Liquidity Pool
        pool = Pool(pat.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT  // liquidityCap value
        ));

        stakeLocker = IStakeLocker(pool.stakeLocker());

        // loan Specifications
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];

        loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        // Stake and finalize pool
        pat.approve(address(bPool), address(stakeLocker), 50 * WAD);
        pat.stake(address(stakeLocker), 50 * WAD);
        pat.finalize(address(pool));  // PD that staked can finalize
        pat.setOpenToPublic(address(pool), true);
        assertEq(uint256(pool.poolState()), 1);  // Finalize
    }

    function test_stake_to_measure_effect_on_stake_date() external {
        uint256 currentDate = block.timestamp;

        pat.setAllowlistStakeLocker(address(pool), address(sam), true);
        pat.setAllowlistStakeLocker(address(pool), address(sid), true);
        sam.approve(address(bPool), address(stakeLocker), uint256(-1));
        sid.approve(address(bPool), address(stakeLocker), uint256(-1));

        assertStake(address(sam), 25 * WAD, 50 * WAD, 50 * WAD, 0, 0);
        assertStake(address(sid), 25 * WAD, 50 * WAD, 50 * WAD, 0, 0);

        assertTrue(sam.try_stake(address(stakeLocker), 5 * WAD)); 
        assertStake(address(sam), 20 * WAD, 55 * WAD, 55 * WAD, 5 * WAD, currentDate);

        currentDate = currentDate + 1 days;
        hevm.warp(currentDate);

        assertTrue(sid.try_stake(address(stakeLocker), 4 * WAD));
        assertStake(address(sid), 21 * WAD, 59 * WAD, 59 * WAD, 4 * WAD, currentDate);

        uint256 oldStakeDate = stakeLocker.stakeDate(address(sam));
        uint256 newStakeDate = getNewStakeDate(address(sam), 5 * WAD);

        assertTrue(sam.try_stake(address(stakeLocker), 5 * WAD)); 

        assertStake(address(sam), 15 * WAD, 64 * WAD, 64 * WAD, 10 * WAD, newStakeDate);
        assertEq(newStakeDate - oldStakeDate, 12 hours);  // coef will be 0.5 days.

        currentDate = currentDate + 5 days;
        hevm.warp(currentDate);

        oldStakeDate = stakeLocker.stakeDate(address(sid));
        newStakeDate = getNewStakeDate(address(sid), 16 * WAD);
        assertTrue(sid.try_stake(address(stakeLocker), 16 * WAD));
        assertStake(address(sid), 5 * WAD, 80 * WAD, 80 * WAD, 20 * WAD, newStakeDate);
        assertEq(newStakeDate - oldStakeDate, 96 hours);  // coef will be 0.8 days. 4 days
    }

    function getNewStakeDate(address who, uint256 amt) public returns(uint256 newStakeDate) {
        uint256 stkDate = stakeLocker.stakeDate(who);
        uint256 coef = stakeLocker.balanceOf(who) + amt == 0 ? 0 : (WAD * amt) / (stakeLocker.balanceOf(who) + amt);
        newStakeDate = stkDate + (((now - stkDate) * coef) / WAD);
    }

    function assertStake(address staker, uint256 staker_bPoolBal, uint256 sl_bPoolBal, uint256 sl_totalSupply, uint256 staker_slBal, uint256 staker_slStakeDate) public {
        assertEq(bPool.balanceOf(staker),                staker_bPoolBal,     "Incorrect balance of staker");
        assertEq(bPool.balanceOf(address(stakeLocker)),  sl_bPoolBal,         "Incorrect balance of stake locker");
        assertEq(stakeLocker.totalSupply(),              sl_totalSupply,      "Incorrect total supply of stake locker");
        assertEq(stakeLocker.balanceOf(staker),          staker_slBal,        "Incorrect balance of staker for stake locker");
        assertEq(stakeLocker.stakeDate(staker),          staker_slStakeDate,  "Incorrect stake date for staker");
    }

    function test_stake_paused() public {
        pat.setAllowlistStakeLocker(address(pool), address(sam), true);
        sam.approve(address(bPool), address(stakeLocker), 20 * WAD);

        // Pause StakeLocker and attempt stake()
        assertTrue( pat.try_pause(address(stakeLocker)));
        assertTrue(!sam.try_stake(address(stakeLocker), 10 * WAD));
        assertEq(stakeLocker.balanceOf(address(sam)),   0 * WAD);

        // Unpause StakeLocker and stake()
        assertTrue(pat.try_unpause(address(stakeLocker)));
        assertTrue(sam.try_stake(address(stakeLocker), 10 * WAD));
        assertEq(stakeLocker.balanceOf(address(sam)),  10 * WAD);

        // Pause protocol and attempt to stake()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_stake(address(stakeLocker), 10 * WAD));
        assertEq(stakeLocker.balanceOf(address(sam)),   10 * WAD);

        // Unpause protocol and stake()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_stake(address(stakeLocker), 10 * WAD));
        assertEq(stakeLocker.balanceOf(address(sam)),  20 * WAD);
    }

    function test_stake() public {
        uint256 startDate = block.timestamp;

        assertTrue(!sam.try_stake(address(stakeLocker),   25 * WAD));  // Hasn't approved BPTs
        sam.approve(address(bPool), address(stakeLocker), 25 * WAD);

        assertTrue(!sam.try_stake(address(stakeLocker),   25 * WAD));  // Isn't yet allowlisted

        pat.setAllowlistStakeLocker(address(pool), address(sam), true);

        assertEq(bPool.balanceOf(address(sam)),         25 * WAD);
        assertEq(bPool.balanceOf(address(stakeLocker)), 50 * WAD);  // PD stake
        assertEq(stakeLocker.totalSupply(),             50 * WAD);
        assertEq(stakeLocker.balanceOf(address(sam)),          0);
        assertEq(stakeLocker.stakeDate(address(sam)),          0);

        assertTrue(sam.try_stake(address(stakeLocker), 25 * WAD));  

        assertEq(bPool.balanceOf(address(sam)),                 0);
        assertEq(bPool.balanceOf(address(stakeLocker)),  75 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),              75 * WAD);
        assertEq(stakeLocker.balanceOf(address(sam)),    25 * WAD);
        assertEq(stakeLocker.stakeDate(address(sam)),   startDate);

        sid.approve(address(bPool), address(stakeLocker), 25 * WAD);  

        assertTrue(!sid.try_stake(address(stakeLocker), 25 * WAD)); // Isn't allowlisted

        // Open StakeLocker to public
        assertTrue(!stakeLocker.openToPublic());
        assertTrue(!pam.try_openStakeLockerToPublic(address(stakeLocker)));
        assertTrue( pat.try_openStakeLockerToPublic(address(stakeLocker)));
        assertTrue( stakeLocker.openToPublic());
        assertTrue(!stakeLocker.allowed(address(sid)));  // Dan is not an allowed Staker, but StakeLocker is now open to public

        assertEq(bPool.balanceOf(address(sid)),         25 * WAD);
        assertEq(bPool.balanceOf(address(stakeLocker)), 75 * WAD);  // PD stake
        assertEq(stakeLocker.totalSupply(),             75 * WAD);
        assertEq(stakeLocker.balanceOf(address(sid)),          0);
        assertEq(stakeLocker.stakeDate(address(sid)),          0);

        assertTrue(sid.try_stake(address(stakeLocker), 25 * WAD));  

        assertEq(bPool.balanceOf(address(sid)),                 0);
        assertEq(bPool.balanceOf(address(stakeLocker)), 100 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),             100 * WAD);
        assertEq(stakeLocker.balanceOf(address(sid)),    25 * WAD);
        assertEq(stakeLocker.stakeDate(address(sid)),   startDate);
    }

    function test_withdrawFunds_protocol_paused() public {
        // Add Staker to allowlist
        pat.setAllowlistStakeLocker(address(pool), address(sam), true);

        // Stake tokens
        sam.approve(address(bPool), address(stakeLocker), 25 * WAD); 
        assertTrue(sam.try_stake(address(stakeLocker), 25 * WAD));

        // Pause protocol and attempt withdrawFunds()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_withdrawFunds(address(stakeLocker)));

        // Unpause protocol and withdrawFunds()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_withdrawFunds(address(stakeLocker)));
    }

    function test_unstake_cooldown() public {

        pat.setAllowlistStakeLocker(address(pool), address(sam), true); // Add Staker to allowlist

        sam.approve(address(bPool), address(stakeLocker), 15 * WAD); // Stake tokens
        assertTrue(sam.try_stake(address(stakeLocker), 15 * WAD));

        hevm.warp(block.timestamp + stakeLocker.lockupPeriod());  // Warp to end of lockup for test

        gov.setStakerCooldownPeriod(10 days);

        uint256 amt = 5 * WAD; // 1/3 of stake so unstake can happen thrice

        uint256 start = block.timestamp;

        assertTrue(!sam.try_unstake(address(stakeLocker), amt),    "Should fail to unstake 10 WAD because user has to intendToWithdraw");
        assertTrue( sam.try_intendToUnstake(address(stakeLocker)), "Failed to intend to unstake");
        assertEq(stakeLocker.unstakeCooldown(address(sam)), start);
        assertTrue(!sam.try_unstake(address(stakeLocker), amt),    "Should fail to unstake before cooldown period has passed");

        // Just before cooldown ends
        hevm.warp(start + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), amt), "Should fail to unstake before cooldown period has passed");

        // Right when cooldown ends
        hevm.warp(start + globals.stakerCooldownPeriod());
        assertTrue(sam.try_unstake(address(stakeLocker), amt), "Should be able to unstake during unstake window");

        // Still within Staker unstake window
        hevm.warp(start + globals.stakerCooldownPeriod() + 1);
        assertTrue(sam.try_unstake(address(stakeLocker), amt), "Should be able to unstake funds again during cooldown window");

        // Second after Staker unstake window ends
        hevm.warp(start + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow() + 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), amt), "Should fail to unstake funds because now past unstake window");

        uint256 newStart = block.timestamp;

        // Intend to unstake
        assertTrue(sam.try_intendToUnstake(address(stakeLocker)), "Failed to intend to unstake");

        // After cooldown ends but after unstake window
        hevm.warp(newStart + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow() + 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), amt), "Should fail to unstake after unstake window has passed");

        // Last second of Staker unstake window
        hevm.warp(newStart + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow());
        assertTrue(sam.try_unstake(address(stakeLocker), amt), "Should be able to unstake during unstake window");
    }

    function test_stake_transfer_restrictions() public {

        pat.setAllowlistStakeLocker(address(pool), address(sam), true); // Add Staker to allowlist

        // transfer() checks

        sam.approve(address(bPool), address(stakeLocker), 25 * WAD); // Stake tokens
        assertTrue(sam.try_stake(address(stakeLocker), 25 * WAD));

        make_transferrable(sam, stakeLocker);

        // Pause protocol and attempt to transfer FDTs
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_transfer(address(stakeLocker), address(leo), 1 * WAD));

        // Unpause protocol and transfer FDTs
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_transfer(address(stakeLocker), address(leo), 1 * WAD));

        make_transferrable(sam, stakeLocker);
        assertTrue(sam.try_transfer(address(stakeLocker), address(pat), 1 * WAD)); // Yes transfer to pool delegate
    }

    function make_transferrable(Staker staker, IStakeLocker stakeLocker) public {
        uint256 currentTime = block.timestamp;
        assertTrue(staker.try_intendToUnstake(address(stakeLocker)));
        assertEq(      stakeLocker.unstakeCooldown(address(staker)), currentTime, "Incorrect value set");
        hevm.warp(currentTime + globals.stakerCooldownPeriod());
    }

    function test_stake_transfer_stakeDate() public {

        // Ignore cooldown for this test
        gov.setStakerUnstakeWindow(MAX_UINT);

        uint256 start = block.timestamp;

        pat.setAllowlistStakeLocker(address(pool), address(sam), true); // Add Staker to allowlist

        sam.approve(address(bPool), address(stakeLocker), 25 * WAD); // Stake tokens
        sam.stake(address(stakeLocker), 25 * WAD);

        pat.setAllowlistStakeLocker(address(pool), address(leo), true); // Add leo to allowlist

        assertEq(stakeLocker.stakeDate(address(sam)), start);  // Che just staked
        assertEq(stakeLocker.stakeDate(address(leo)),     0);  // Ali has not staked

        assertTrue(sam.try_intendToUnstake(address(stakeLocker)));
        hevm.warp(start + globals.stakerCooldownPeriod() + 1 days);
        
        sam.transfer(address(stakeLocker), address(leo), 1 * WAD); // Transfer to Ali

        assertEq(stakeLocker.stakeDate(address(sam)),          start);  // Che's date does not change
        assertEq(stakeLocker.stakeDate(address(leo)), start + globals.stakerCooldownPeriod() + 1 days);  // Ali just got sent FDTs which is effectively "staking"

        hevm.warp(start);
        assertTrue(sam.try_intendToUnstake(address(stakeLocker)));
        hevm.warp(start + globals.stakerCooldownPeriod() + 3 days);

        sam.transfer(address(stakeLocker), address(leo), 1 * WAD); // Transfer to Ali

        assertEq(stakeLocker.stakeDate(address(sam)),          start);  // Che's date does not change
        assertEq(stakeLocker.stakeDate(address(leo)), start + globals.stakerCooldownPeriod() + 2 days);  // Ali stake date = 1/(1+1) * (3 days + coolDown - (1 days + cooldown)) + (1 days + cooldown) = 1/2 * (3 + 10 - (1 + 10)) + (1+10) = 12 days past start
    }

    function test_stake_transfer_recipient_withdrawing() public {
        pat.openStakeLockerToPublic(address(stakeLocker));

        uint256 start = block.timestamp;
        uint256 stakeAmt = 25 * WAD;

        // Stake BPTs into StakeLocker
        sam.approve(address(bPool), address(stakeLocker), stakeAmt);
        sam.stake(address(stakeLocker), stakeAmt);
        sid.approve(address(bPool), address(stakeLocker), stakeAmt);
        sid.stake(address(stakeLocker), stakeAmt);

         // Staker (Dan) initiates unstake
        assertTrue(sid.try_intendToUnstake(address(stakeLocker)));
        assertEq(stakeLocker.unstakeCooldown(address(sid)), start);

        // Staker (Che) fails to transfer to Staker (Dan) who is currently unstaking
        assertTrue(!sam.try_transfer(address(stakeLocker), address(sid), stakeAmt));
        hevm.warp(start + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow());  // Very end of Staker unstake window
        assertTrue(!sam.try_transfer(address(stakeLocker), address(sid), stakeAmt));

        // Staker (Che) successfully transfers to Staker (Dan) who is now outside unstake window
        hevm.warp(start + globals.stakerCooldownPeriod() + globals.stakerUnstakeWindow() + 1);  // Second after Staker unstake window ends
        assertTrue(sam.try_transfer(address(stakeLocker), address(sid), stakeAmt));

        // Check balances and stake dates are correct
        assertEq(stakeLocker.balanceOf(address(sam)), 0);
        assertEq(stakeLocker.balanceOf(address(sid)), stakeAmt * 2);
        uint256 newStakeDate = start + (block.timestamp - start) * (stakeAmt) / ((stakeAmt) + (stakeAmt));
        assertEq(stakeLocker.stakeDate(address(sam)), start);         // Stays the same
        assertEq(stakeLocker.stakeDate(address(sid)), newStakeDate);  // Gets updated
    }

    function setUpLoanAndRepay() public {
        mint("USDC", address(leo), 10_000_000 * USD);  // Mint USDC to LP
        leo.approve(USDC, address(pool), MAX_UINT);    // LP approves USDC

        leo.deposit(address(pool), 10_000_000 * USD);                                      // LP deposits 10m USDC to Pool
        pat.fundLoan(address(pool), address(loan), address(dlFactory), 10_000_000 * USD);  // PD funds loan for 10m USDC

        uint cReq = loan.collateralRequiredForDrawdown(10_000_000 * USD);  // WETH required for 100_000_000 USDC drawdown on loan
        mint("WETH", address(bob), cReq);                                  // Mint WETH to borrower
        bob.approve(WETH, address(loan), MAX_UINT);                        // Borrower approves WETH
        bob.drawdown(address(loan), 10_000_000 * USD);                     // Borrower draws down 10m USDC

        mint("USDC", address(bob), 10_000_000 * USD);  // Mint USDC to Borrower for repayment plus interest         
        bob.approve(USDC, address(loan), MAX_UINT);    // Borrower approves USDC
        bob.makeFullPayment(address(loan));            // Borrower makes full payment, which includes interest

        pat.claim(address(pool), address(loan),  address(dlFactory));  // PD claims interest, distributing funds to stakeLocker
    }

    function test_unstake() public {
        uint256 stakeDate = block.timestamp;

        pat.setAllowlistStakeLocker(address(pool), address(sam), true);
        sam.approve(address(bPool), address(stakeLocker), 25 * WAD);
        sam.stake(address(stakeLocker), 25 * WAD); 

        assertEq(IERC20(USDC).balanceOf(address(sam)),          0);
        assertEq(bPool.balanceOf(address(sam)),                 0);
        assertEq(bPool.balanceOf(address(stakeLocker)),  75 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),              75 * WAD);
        assertEq(stakeLocker.balanceOf(address(sam)),    25 * WAD);
        assertEq(stakeLocker.stakeDate(address(sam)),   stakeDate);

        setUpLoanAndRepay();
        assertTrue(!sue.try_intendToUnstake(address(stakeLocker)));  // Unstake will not work as sue doesn't possess any balance.
        assertTrue( sam.try_intendToUnstake(address(stakeLocker)));

        hevm.warp(stakeDate + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), 25 * WAD));  // Staker cannot unstake BPTs until stakerCooldownPeriod has passed

        hevm.warp(stakeDate + globals.stakerCooldownPeriod());
        assertTrue(!sam.try_unstake(address(stakeLocker), 25 * WAD));  // Still cannot unstake because of lockup period

        hevm.warp(stakeDate + stakeLocker.lockupPeriod() - globals.stakerCooldownPeriod());  // Warp to first time that user can cooldown and unstake and will be after lockup
        uint256 cooldownTimestamp = block.timestamp;
        assertTrue(sam.try_intendToUnstake(address(stakeLocker)));

        hevm.warp(cooldownTimestamp + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), 25 * WAD));  // Staker cannot unstake BPTs until stakerCooldownPeriod has passed

        hevm.warp(cooldownTimestamp + globals.stakerCooldownPeriod());  // Now user is able to unstake

        uint256 totalStakerEarnings    = IERC20(USDC).balanceOf(address(stakeLocker));
        uint256 cheStakerEarnings_FDT  = stakeLocker.withdrawableFundsOf(address(sam));
        uint256 cheStakerEarnings_calc = totalStakerEarnings * (25 * WAD) / (75 * WAD);  // Che's portion of staker earnings

        // Pause protocol and attempt unstake()
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!sam.try_unstake(address(stakeLocker), 25 * WAD));
        
        // Unpause protocol and unstake()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(sam.try_unstake(address(stakeLocker), 25 * WAD));  // Staker unstakes all BPTs

        withinPrecision(cheStakerEarnings_FDT, cheStakerEarnings_calc, 9);

        assertEq(IERC20(USDC).balanceOf(address(sam)),                               cheStakerEarnings_FDT);  // Che got portion of interest
        assertEq(IERC20(USDC).balanceOf(address(stakeLocker)), totalStakerEarnings - cheStakerEarnings_FDT);  // Interest was transferred out of SL

        assertEq(bPool.balanceOf(address(sam)),          25 * WAD);  // Che unstaked BPTs
        assertEq(bPool.balanceOf(address(stakeLocker)),  50 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),              50 * WAD);  // Total supply of stake tokens has decreased
        assertEq(stakeLocker.balanceOf(address(sam)),           0);  // Che has no stake tokens after unstake
        assertEq(stakeLocker.stakeDate(address(sam)),   stakeDate);  // StakeDate remains unchanged (doesn't matter since balanceOf == 0 on next stake)
    }

    function setUpLoanMakeOnePaymentAndDefault() public returns (uint256 interestPaid) {
        // Fund the pool
        mint("USDC", address(leo), 20_000_000 * USD);
        leo.approve(USDC, address(pool), MAX_UINT);
        leo.deposit(address(pool), 10_000_000 * USD);

        // Fund the loan
        pat.fundLoan(address(pool), address(loan), address(dlFactory), 1_000_000 * USD);
        uint cReq = loan.collateralRequiredForDrawdown(1_000_000 * USD);

        // Drawdown loan
        mint("WETH", address(bob), cReq);
        bob.approve(WETH, address(loan), MAX_UINT);
        bob.approve(USDC, address(loan), MAX_UINT);
        bob.drawdown(address(loan), 1_000_000 * USD);

        uint256 preBal = IERC20(USDC).balanceOf(address(bob));
        bob.makePayment(address(loan));  // Make one payment to register interest for Staker
        interestPaid = preBal.sub(IERC20(USDC).balanceOf(address(bob)));

        // Warp to late payment
        uint256 start = block.timestamp;
        uint256 nextPaymentDue = loan.nextPaymentDue();
        uint256 gracePeriod = globals.gracePeriod();
        hevm.warp(start + nextPaymentDue + gracePeriod + 1);

        // Trigger default
        pat.triggerDefault(address(pool), address(loan), address(dlFactory));
    }

    function test_staker_fdt_accounting(uint256 stakeAmount) public {
        TestObj memory stakeLockerBal;        // StakeLocker total balance of BPTs
        TestObj memory fdtTotalSupply;        // Total Supply of FDTs
        TestObj memory stakerFDTBal;          // Staker FDT balance
        TestObj memory fundsTokenBal;         // FDT accounting of interst earned
        TestObj memory withdrawableFundsOf;   // Interest earned by Staker
        TestObj memory bptLosses;             // FDT accounting of losses from burning
        TestObj memory recognizableLossesOf;  // Recognizable losses of Staker

        uint256 bptMin = WAD / 10_000_000;

        stakeAmount = constrictToRange(stakeAmount,  bptMin, bPool.balanceOf(address(sam)), true);  // 25 WAD max, 1/10m WAD min, or zero (min is roughly equal to 10 cents) (non-zero)

        pat.setAllowlistStakeLocker(address(pool), address(sam), true);
        pat.setAllowlistStakeLocker(address(pool), address(sid), true);
        pat.setAllowlistStakeLocker(address(pool), address(sue), true);

        sam.approve(address(bPool), address(stakeLocker), MAX_UINT);
        sid.approve(address(bPool), address(stakeLocker), MAX_UINT);
        sue.approve(address(bPool), address(stakeLocker), MAX_UINT);

        sam.stake(address(stakeLocker), stakeAmount);  // Che stakes before default, unstakes min amount
        sid.stake(address(stakeLocker), 25 * WAD);     // Dan stakes before default, unstakes full amount

        uint256 interestPaid = setUpLoanMakeOnePaymentAndDefault();  // This does not affect any Pool accounting
        
        /*****************************************************/
        /*** Make Claim, Update StakeLocker FDT Accounting ***/
        /*****************************************************/

        // Pre-claim FDT and StakeLocker checks (Che only)
        stakeLockerBal.pre       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.pre       = stakeLocker.totalSupply();
        stakerFDTBal.pre         = stakeLocker.balanceOf(address(sam));
        fundsTokenBal.pre        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.pre  = stakeLocker.withdrawableFundsOf(address(sam));
        bptLosses.pre            = stakeLocker.bptLosses();
        recognizableLossesOf.pre = stakeLocker.recognizableLossesOf(address(sam));

        assertEq(stakeLockerBal.pre,      stakeAmount + 75 * WAD);  // Che + Dan + Sid stake
        assertEq(fdtTotalSupply.pre,      stakeAmount + 75 * WAD);  // FDT Supply == amount staked
        assertEq(stakerFDTBal.pre,                   stakeAmount);  // Che FDT balance == amount staked
        assertEq(fundsTokenBal.pre,                            0);  // Claim hasnt been made yet - interest not realized
        assertEq(withdrawableFundsOf.pre,                      0);  // Claim hasnt been made yet - interest not realized
        assertEq(bptLosses.pre,                                0);  // Claim hasnt been made yet - losses   not realized
        assertEq(recognizableLossesOf.pre,                     0);  // Claim hasnt been made yet - losses   not realized
        
        pat.claim(address(pool), address(loan),  address(dlFactory));  // Pool Delegate claims funds, updating accounting for interest and losses from Loan

        // Post-claim FDT and StakeLocker checks (Che only)
        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(sam));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(sam));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(sam));

        uint256 stakingRevenue = interestPaid * pool.stakingFee() / 10_000;  // Portion of interest that goes to the StakeLocker

        assertTrue(stakeLockerBal.post < stakeLockerBal.pre);  // BPTs were burned to cover losses

        assertEq(fdtTotalSupply.post,                                   stakeAmount + 75 * WAD);  // FDT Supply == total amount staked
        assertEq(stakerFDTBal.post,                                                stakeAmount);  // Che FDT balance == amount staked
        assertEq(fundsTokenBal.post,                                            stakingRevenue);  // Interest claimed
        assertEq(withdrawableFundsOf.post,  stakingRevenue * stakeAmount / fdtTotalSupply.post);  // Che claim on interest
        assertEq(bptLosses.post,                      stakeLockerBal.pre - stakeLockerBal.post);  // Losses registered in StakeLocker
        assertEq(recognizableLossesOf.post, bptLosses.post * stakeAmount / fdtTotalSupply.post);  // Che's recognizable losses

        /**************************************************************/
        /*** Staker Post-Loss Minimum Unstake Accounting (Che Only) ***/
        /**************************************************************/

        // Pre-unstake FDT and StakeLocker checks (update variables)
        stakeLockerBal.pre       = stakeLockerBal.post;
        fdtTotalSupply.pre       = fdtTotalSupply.post;
        stakerFDTBal.pre         = stakerFDTBal.post; 
        fundsTokenBal.pre        = fundsTokenBal.post;
        withdrawableFundsOf.pre  = withdrawableFundsOf.post;
        bptLosses.pre            = bptLosses.post;  
        recognizableLossesOf.pre = recognizableLossesOf.post;

        assertEq(bPool.balanceOf(address(sam)),        25 * WAD - stakeAmount);  // Starting balance minus staked amount
        assertEq(IERC20(USDC).balanceOf(address(sam)),                      0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  fundsTokenBal.pre * stakeAmount / fdtTotalSupply.pre);  // Assert FDT interest accounting
        assertEq(recognizableLossesOf.pre,     bptLosses.pre * stakeAmount / fdtTotalSupply.pre);  // Assert FDT loss     accounting

        // re-using the variable to avoid stack too deep issue.
        interestPaid = block.timestamp;

        assertTrue(sam.try_intendToUnstake(address(stakeLocker)));
        assertEq(stakeLocker.unstakeCooldown(address(sam)), interestPaid);
        hevm.warp(interestPaid + globals.stakerCooldownPeriod());
        assertTrue(!sam.try_unstake(address(stakeLocker), recognizableLossesOf.pre - 1));  // Cannot withdraw less than the losses incurred
        hevm.warp(interestPaid + globals.stakerCooldownPeriod() - 1);
        assertTrue(!sam.try_unstake(address(stakeLocker), recognizableLossesOf.pre));
        hevm.warp(interestPaid + globals.stakerCooldownPeriod());
        assertTrue(sam.try_unstake(address(stakeLocker), recognizableLossesOf.pre));  // Withdraw lowest possible amount (amt == recognizableLosses), FDTs burned to cover losses, no BPTs left to withdraw

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(sam));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(sam));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(sam));

        assertEq(stakeLockerBal.post,                  stakeAmount + 75 * WAD - bptLosses.pre);  // Che + Dan + Sid stake minus burned BPTs
        assertEq(fdtTotalSupply.post,       stakeAmount + 75 * WAD - recognizableLossesOf.pre);  // FDT Supply == amount staked
        assertEq(stakerFDTBal.post,                    stakeAmount - recognizableLossesOf.pre);  // Che FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                 stakingRevenue - withdrawableFundsOf.pre);  // Interest has been claimed 
        assertEq(withdrawableFundsOf.post,                                                  0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                     bptLosses.pre - recognizableLossesOf.pre);  // Losses accounting has been updated
        assertEq(recognizableLossesOf.post,                                                 0);  // Losses have been recognized

        assertEq(bPool.balanceOf(address(sam)),         25 * WAD - stakeAmount);  // Starting balance minus staked amount (same as before unstake, meaning no BPTs were returned to Che)
        assertEq(IERC20(USDC).balanceOf(address(sam)), withdrawableFundsOf.pre);  // USDC balance

        /******************************************************/
        /*** Staker Post-Loss Unstake Accounting (Dan Only) ***/
        /******************************************************/

        uint256 initialFundsTokenBal = fundsTokenBal.pre;  // Need this for asserting pre-unstake FDT
        uint256 initialLosses        = bptLosses.pre;      // Need this for asserting pre-unstake FDT

        // Pre-unstake FDT and StakeLocker checks (update variables)
        stakeLockerBal.pre       = stakeLockerBal.post;
        fdtTotalSupply.pre       = fdtTotalSupply.post;
        stakerFDTBal.pre         = stakeLocker.balanceOf(address(sid));
        fundsTokenBal.pre        = fundsTokenBal.post;
        withdrawableFundsOf.pre  = stakeLocker.withdrawableFundsOf(address(sid));
        bptLosses.pre            = bptLosses.post;  
        recognizableLossesOf.pre = stakeLocker.recognizableLossesOf(address(sid));

        assertEq(bPool.balanceOf(address(sid)),        0);  // Staked entire balance
        assertEq(IERC20(USDC).balanceOf(address(sid)), 0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  initialFundsTokenBal * 25 * WAD / (75 * WAD + stakeAmount));  // Assert FDT interest accounting (have to use manual totalSupply because of Che unstake)
        assertEq(recognizableLossesOf.pre,        initialLosses * 25 * WAD / (75 * WAD + stakeAmount));  // Assert FDT loss     accounting (have to use manual totalSupply because of Che unstake)

        interestPaid = block.timestamp;

        assertTrue(sid.try_intendToUnstake(address(stakeLocker)));
        assertEq(stakeLocker.unstakeCooldown(address(sid)), interestPaid);
        hevm.warp(interestPaid + globals.stakerCooldownPeriod() + 1);
        assertTrue(!sid.try_unstake(address(stakeLocker), stakerFDTBal.pre + 1));  // Cannot withdraw more than current FDT bal
        assertTrue( sid.try_unstake(address(stakeLocker), stakerFDTBal.pre));      // Withdraw remaining BPTs

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(sid));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(sid));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(sid));

        assertEq(stakeLockerBal.post,      stakeLockerBal.pre - (25 * WAD - recognizableLossesOf.pre));  // Dan's unstake amount minus his losses
        assertEq(fdtTotalSupply.post,                                   fdtTotalSupply.pre - 25 * WAD);  // FDT Supply = previous FDT total supply - unstake amount
        assertEq(stakerFDTBal.post,                                                                 0);  // Dan's entire FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                      fundsTokenBal.pre - withdrawableFundsOf.pre);  // Interest has been claimed 
        assertEq(withdrawableFundsOf.post,                                                          0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                             bptLosses.pre - recognizableLossesOf.pre);  // Losses accounting has been updated
        assertEq(recognizableLossesOf.post,                                                         0);  // Losses have been recognized

        assertEq(bPool.balanceOf(address(sid)),        25 * WAD - recognizableLossesOf.pre);  // Starting balance minus losses
        assertEq(IERC20(USDC).balanceOf(address(sid)),             withdrawableFundsOf.pre);  // USDC balance from interest

        /************************************************************/
        /*** Post-Loss Staker Stake/Unstake Accounting (Eli Only) ***/
        /************************************************************/
        // Ensure that Eli has no loss exposure if he stakes after a default has already occured
        uint256 eliStakeAmount = bPool.balanceOf(address(sid));
        sid.transfer(address(bPool), address(sue), eliStakeAmount);  // Dan sends Eli a balance of BPTs so he can stake

        sue.stake(address(stakeLocker), eliStakeAmount);

        // Pre-unstake FDT and StakeLocker checks (update variables)
        stakeLockerBal.pre       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.pre       = stakeLocker.totalSupply();
        stakerFDTBal.pre         = stakeLocker.balanceOf(address(sue));
        fundsTokenBal.pre        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.pre  = stakeLocker.withdrawableFundsOf(address(sue));
        bptLosses.pre            = stakeLocker.bptLosses();
        recognizableLossesOf.pre = stakeLocker.recognizableLossesOf(address(sue));

        assertEq(bPool.balanceOf(address(sue)),        0);  // Staked entire balance
        assertEq(IERC20(USDC).balanceOf(address(sue)), 0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  0);  // Assert FDT interest accounting
        assertEq(recognizableLossesOf.pre, 0);  // Assert FDT loss     accounting

        hevm.warp(block.timestamp + stakeLocker.lockupPeriod());  // Warp to the end of the lockup

        assertTrue(sue.try_intendToUnstake(address(stakeLocker)));
        hevm.warp(block.timestamp + globals.stakerCooldownPeriod() + 1);
        sue.unstake(address(stakeLocker), eliStakeAmount);  // Unstake entire balance

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(sue));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(sue));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(sue));

        assertEq(stakeLockerBal.post,      stakeLockerBal.pre - eliStakeAmount);  // Eli recovered full stake
        assertEq(fdtTotalSupply.post,      fdtTotalSupply.pre - eliStakeAmount);  // FDT Supply minus Eli's full stake
        assertEq(stakerFDTBal.post,                                          0);  // Eli FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                         fundsTokenBal.pre);  // No interest has been claimed 
        assertEq(withdrawableFundsOf.post,                                   0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                                 bptLosses.pre);  // Losses accounting has not changed
        assertEq(recognizableLossesOf.post,                                  0);  // Losses have been "recognized" (there were none)

        assertEq(bPool.balanceOf(address(sue)),        eliStakeAmount);  // Eli recovered full stake
        assertEq(IERC20(USDC).balanceOf(address(sue)),              0);  // USDC balance from interest (none)
    }
} 
