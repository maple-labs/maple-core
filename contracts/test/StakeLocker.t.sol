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
    LP                                     ali;
    PoolDelegate                           sid;
    Staker                                 che;
    Staker                                 dan;
    Staker                                 eli;
    EmergencyAdmin                         mic;

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

    uint256 constant public MAX_UINT = uint(-1);

    function setUp() public {

        bob            = new Borrower();                                                // Actor: Borrower of the Loan.
        gov            = new Governor();                                                // Actor: Governor of Maple.
        ali            = new LP();                                                      // Actor: Liquidity provider.
        sid            = new PoolDelegate();                                            // Actor: Manager of the Pool.
        che            = new Staker();                                                  // Actor: Stakes BPTs in Pool.
        dan            = new Staker();                                                  // Actor: Stakes BPTs in Pool.
        eli            = new Staker();                                                  // Actor: Stakes BPTs in Pool.
        mic            = new EmergencyAdmin();                                          // Actor: Emergency Admin of the protocol.

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl), BPOOL_FACTORY);
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

        gov.setPoolDelegateAllowlist(address(sid), true);
        gov.setMapleTreasury(address(trs));
        gov.setAdmin(address(mic));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), 50 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(che), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
        bPool.transfer(address(dan), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool

        // Set Globals
        gov.setCalc(address(repaymentCalc), true);
        gov.setCalc(address(lateFeeCalc),   true);
        gov.setCalc(address(premiumCalc),   true);
        gov.setCollateralAsset(WETH,        true);
        gov.setLoanAsset(USDC,              true);
        gov.setSwapOutRequired(1_000_000);

        // Create Liquidity Pool
        pool = Pool(sid.createPool(
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
        sid.approve(address(bPool), address(stakeLocker), 50 * WAD);
        sid.stake(address(stakeLocker), 50 * WAD);
        sid.finalize(address(pool));  // PD that staked can finalize
        sid.openPoolToPublic(address(pool));
        assertEq(uint256(pool.poolState()), 1);  // Finalize
    }

    function test_stake_to_measure_effect_on_stake_date() external {
        uint256 currentDate = block.timestamp;

        sid.setAllowlistStakeLocker(address(pool), address(che), true);
        sid.setAllowlistStakeLocker(address(pool), address(dan), true);
        che.approve(address(bPool), address(stakeLocker), uint256(-1));
        dan.approve(address(bPool), address(stakeLocker), uint256(-1));

        assertStake(address(che), 25 * WAD, 50 * WAD, 50 * WAD, 0, 0);
        assertStake(address(dan), 25 * WAD, 50 * WAD, 50 * WAD, 0, 0);

        assertTrue(che.try_stake(address(stakeLocker), 5 * WAD)); 
        assertStake(address(che), 20 * WAD, 55 * WAD, 55 * WAD, 5 * WAD, currentDate);
        assertEq(stakeLocker.getUnstakeableBalance(address(che)), 0);

        currentDate = currentDate + 1 days;
        hevm.warp(currentDate);

        assertTrue(dan.try_stake(address(stakeLocker), 4 * WAD));
        assertStake(address(dan), 21 * WAD, 59 * WAD, 59 * WAD, 4 * WAD, currentDate);
        assertEq(stakeLocker.getUnstakeableBalance(address(dan)), 0);

        uint256 oldStakeDate = stakeLocker.stakeDate(address(che));
        uint256 newStakeDate = getNewStakeDate(address(che), 5 * WAD);

        uint256 che_unstakeableBal_before = stakeLocker.getUnstakeableBalance(address(che));
        assertEq(che_unstakeableBal_before, 55555555555555555);

        assertTrue(che.try_stake(address(stakeLocker), 5 * WAD)); 

        uint256 che_unstakeableBal_after = stakeLocker.getUnstakeableBalance(address(che));
        assertEq(che_unstakeableBal_after, che_unstakeableBal_before);

        assertStake(address(che), 15 * WAD, 64 * WAD, 64 * WAD, 10 * WAD, newStakeDate);
        assertEq(newStakeDate - oldStakeDate, 12 hours);  // coef will be 0.5 days.

        currentDate = currentDate + 5 days;
        hevm.warp(currentDate);

        oldStakeDate = stakeLocker.stakeDate(address(dan));
        newStakeDate = getNewStakeDate(address(dan), 16 * WAD);
        assertTrue(dan.try_stake(address(stakeLocker), 16 * WAD));
        assertStake(address(dan), 5 * WAD, 80 * WAD, 80 * WAD, 20 * WAD, newStakeDate);
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

    function test_stake_protocol_paused() public {
        sid.setAllowlistStakeLocker(address(pool), address(che), true);
        che.approve(address(bPool), address(stakeLocker), 25 * WAD);

        // Pause protocol and attempt to stake()
        assertTrue(!globals.protocolPaused());
        assertTrue(mic.try_setProtocolPause(address(globals), true));
        assertTrue(globals.protocolPaused());
        assertTrue(!che.try_stake(address(stakeLocker), 25 * WAD));

        // Unpause protocol and stake()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(che.try_stake(address(stakeLocker), 25 * WAD));
    }

    function test_stake() public {
        uint256 startDate = block.timestamp;

        assertTrue(!che.try_stake(address(stakeLocker),   25 * WAD));  // Hasn't approved BPTs
        che.approve(address(bPool), address(stakeLocker), 25 * WAD);

        assertTrue(!che.try_stake(address(stakeLocker),   25 * WAD));  // Isn't yet allowlisted
        che.approve(address(bPool), address(stakeLocker), 25 * WAD);

        sid.setAllowlistStakeLocker(address(pool), address(che), true);

        assertEq(bPool.balanceOf(address(che)),         25 * WAD);
        assertEq(bPool.balanceOf(address(stakeLocker)), 50 * WAD);  // PD stake
        assertEq(stakeLocker.totalSupply(),             50 * WAD);
        assertEq(stakeLocker.balanceOf(address(che)),          0);
        assertEq(stakeLocker.stakeDate(address(che)),          0);

        assertTrue(che.try_stake(address(stakeLocker), 25 * WAD));  

        assertEq(bPool.balanceOf(address(che)),                 0);
        assertEq(bPool.balanceOf(address(stakeLocker)),  75 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),              75 * WAD);
        assertEq(stakeLocker.balanceOf(address(che)),    25 * WAD);
        assertEq(stakeLocker.stakeDate(address(che)),   startDate);
    }

    function test_withdrawFunds_protocol_paused() public {
        // Add Staker to allowlist
        sid.setAllowlistStakeLocker(address(pool), address(che), true);

        // Stake tokens
        che.approve(address(bPool), address(stakeLocker), 25 * WAD); 
        assertTrue(che.try_stake(address(stakeLocker), 25 * WAD));

        // Pause protocol and attempt withdrawFunds()
        assertTrue(mic.try_setProtocolPause(address(globals), true));
        assertTrue(!che.try_withdrawFunds(address(stakeLocker)));

        // Unpause protocol and withdrawFunds()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(che.try_withdrawFunds(address(stakeLocker)));
    }

    function test_stake_transfer_restrictions() public {

        sid.setAllowlistStakeLocker(address(pool), address(che), true); // Add Staker to allowlist

        // transfer() checks

        che.approve(address(bPool), address(stakeLocker), 25 * WAD); // Stake tokens
        assertTrue(che.try_stake(address(stakeLocker), 25 * WAD));

        make_transferrable(che, stakeLocker);
        assertTrue(!che.try_transfer(address(stakeLocker), address(ali), 1 * WAD)); // No transfer to non-allowlisted user

        sid.setAllowlistStakeLocker(address(pool), address(ali), true); // Add ali to allowlist

        // Pause protocol and attempt to transfer FDTs
        assertTrue(mic.try_setProtocolPause(address(globals), true));
        assertTrue(!che.try_transfer(address(stakeLocker), address(ali), 1 * WAD));

        // Unpause protocol and transfer FDTs
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(che.try_transfer(address(stakeLocker), address(ali), 1 * WAD)); // Yes transfer to allowlisted user

        make_transferrable(che, stakeLocker);
        assertTrue(che.try_transfer(address(stakeLocker), address(sid), 1 * WAD)); // Yes transfer to pool delegate

        // transferFrom() checks
        che.approve(address(stakeLocker), address(dan), 5 * WAD);
        sid.setAllowlistStakeLocker(address(pool), address(ali), false); // Remove ali to allowlist
        sid.setAllowlistStakeLocker(address(pool), address(dan), true); // Add dan to allowlist

        make_transferrable(che, stakeLocker);
        assertTrue(!dan.try_transferFrom(address(stakeLocker), address(che), address(ali), 1 * WAD)); // No transferFrom to non-allowlisted user
        assertTrue(dan.try_transferFrom(address(stakeLocker), address(che), address(dan), 1 * WAD)); // Yes transferFrom to allowlisted user
        make_transferrable(che, stakeLocker);
        assertTrue(dan.try_transferFrom(address(stakeLocker), address(che), address(sid), 1 * WAD)); // Yes transferFrom to pool delegate

    }

    function make_transferrable(Staker staker, IStakeLocker stakeLocker) public {
        uint256 currentTime = block.timestamp;
        assertTrue(staker.try_intendToUnstake(address(stakeLocker)));
        assertEq(      stakeLocker.stakeCooldown(address(staker)), currentTime, "Incorrect value set");
        hevm.warp(currentTime + globals.cooldownPeriod() + 1);
    }

    function test_stake_transfer_stakeDate() public {

        uint256 start = block.timestamp;

        sid.setAllowlistStakeLocker(address(pool), address(che), true); // Add Staker to allowlist

        che.approve(address(bPool), address(stakeLocker), 25 * WAD); // Stake tokens
        che.stake(address(stakeLocker), 25 * WAD);

        sid.setAllowlistStakeLocker(address(pool), address(ali), true); // Add ali to allowlist

        assertEq(stakeLocker.stakeDate(address(che)), start);  // Che just staked
        assertEq(stakeLocker.stakeDate(address(ali)),     0);  // Ali has not staked

        assertTrue(che.try_intendToUnstake(address(stakeLocker)));
        hevm.warp(start + globals.cooldownPeriod() + 1 days);
        
        che.transfer(address(stakeLocker), address(ali), 1 * WAD); // Transfer to Ali

        assertEq(stakeLocker.stakeDate(address(che)),          start);  // Che's date does not change
        assertEq(stakeLocker.stakeDate(address(ali)), start + globals.cooldownPeriod() + 1 days);  // Ali just got sent FDTs which is effectively "staking"

        hevm.warp(start);
        assertTrue(che.try_intendToUnstake(address(stakeLocker)));
        hevm.warp(start + globals.cooldownPeriod() + 3 days);

        che.transfer(address(stakeLocker), address(ali), 1 * WAD); // Transfer to Ali

        assertEq(stakeLocker.stakeDate(address(che)),          start);  // Che's date does not change
        assertEq(stakeLocker.stakeDate(address(ali)), start + globals.cooldownPeriod() + 2 days);  // Ali stake date = 1/(1+1) * (3 days + coolDown - (1 days + cooldown)) + (1 days + cooldown) = 1/2 * (3 + 10 - (1 + 10)) + (1+10) = 12 days past start
    }

    function setUpLoanAndRepay() public {
        mint("USDC", address(ali), 10_000_000 * USD);  // Mint USDC to LP
        ali.approve(USDC, address(pool), MAX_UINT);    // LP approves USDC

        ali.deposit(address(pool), 10_000_000 * USD);                                      // LP deposits 10m USDC to Pool
        sid.fundLoan(address(pool), address(loan), address(dlFactory), 10_000_000 * USD);  // PD funds loan for 10m USDC

        uint cReq = loan.collateralRequiredForDrawdown(10_000_000 * USD);  // WETH required for 100_000_000 USDC drawdown on loan
        mint("WETH", address(bob), cReq);                                  // Mint WETH to borrower
        bob.approve(WETH, address(loan), MAX_UINT);                        // Borrower approves WETH
        bob.drawdown(address(loan), 10_000_000 * USD);                     // Borrower draws down 10m USDC

        mint("USDC", address(bob), 10_000_000 * USD);  // Mint USDC to Borrower for repayment plus interest         
        bob.approve(USDC, address(loan), MAX_UINT);    // Borrower approves USDC
        bob.makeFullPayment(address(loan));            // Borrower makes full payment, which includes interest

        sid.claim(address(pool), address(loan),  address(dlFactory));  // PD claims interest, distributing funds to stakeLocker
    }

    function test_unstake_past_unstakeDelay() public {
        uint256 stakeDate = block.timestamp;

        sid.setAllowlistStakeLocker(address(pool), address(che), true);
        che.approve(address(bPool), address(stakeLocker), 25 * WAD);
        che.stake(address(stakeLocker), 25 * WAD);  

        assertEq(IERC20(USDC).balanceOf(address(che)),          0);
        assertEq(bPool.balanceOf(address(che)),                 0);
        assertEq(bPool.balanceOf(address(stakeLocker)),  75 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),              75 * WAD);
        assertEq(stakeLocker.balanceOf(address(che)),    25 * WAD);
        assertEq(stakeLocker.stakeDate(address(che)),   stakeDate);

        setUpLoanAndRepay();
        assertTrue(!eli.try_intendToUnstake(address(stakeLocker)));  // Unstake will not work as eli doesn't possess any balance.
        assertTrue( che.try_intendToUnstake(address(stakeLocker)));
        hevm.warp(stakeDate + globals.unstakeDelay() - 1);
        assertTrue(!che.try_unstake(address(stakeLocker), 25 * WAD));  // Staker cannot unstake 100% of BPTs until unstakeDelay has passed
        hevm.warp(stakeDate + globals.unstakeDelay());

        uint256 totalStakerEarnings    = IERC20(USDC).balanceOf(address(stakeLocker));
        uint256 cheStakerEarnings_FDT  = stakeLocker.withdrawableFundsOf(address(che));
        uint256 cheStakerEarnings_calc = totalStakerEarnings * (25 * WAD) / (75 * WAD);  // Che's portion of staker earnings

        // Pause protocol and attempt unstake()
        assertTrue(mic.try_setProtocolPause(address(globals), true));
        assertTrue(!che.try_unstake(address(stakeLocker), 25 * WAD));
        
        // Unpause protocol and unstake()
        assertTrue(mic.try_setProtocolPause(address(globals), false));
        assertTrue(che.try_unstake(address(stakeLocker), 25 * WAD));  // Staker unstakes all BPTs

        withinPrecision(cheStakerEarnings_FDT, cheStakerEarnings_calc, 9);

        assertEq(IERC20(USDC).balanceOf(address(che)),                               cheStakerEarnings_FDT);  // Che got portion of interest
        assertEq(IERC20(USDC).balanceOf(address(stakeLocker)), totalStakerEarnings - cheStakerEarnings_FDT);  // Interest was transferred out of SL

        assertEq(bPool.balanceOf(address(che)),          25 * WAD);  // Che unstaked BPTs
        assertEq(bPool.balanceOf(address(stakeLocker)),  50 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),              50 * WAD);  // Total supply of stake tokens has decreased
        assertEq(stakeLocker.balanceOf(address(che)),           0);  // Che has no stake tokens after unstake
        assertEq(stakeLocker.stakeDate(address(che)),   stakeDate);  // StakeDate remains unchanged (doesn't matter since balanceOf == 0 on next stake)
    }

    function test_unstakeableBalance(uint256 stakeAmount, uint256 dTime, uint256 stakeAmount2, uint256 dTime2) public {
        TestObj memory unstakeableBal;

        uint256 unstakeDelay = globals.unstakeDelay();
        uint256 bptMin = WAD / 10_000_000;

        stakeAmount  = constrictToRange(stakeAmount,  bptMin, bPool.balanceOf(address(che)) / 2, true);  // 12.5 WAD max, 1/10m WAD min, or zero (min is roughly equal to 10 cents)   (non-zero to avoid division by zero in stakeDate)
        stakeAmount2 = constrictToRange(stakeAmount2, bptMin, bPool.balanceOf(address(che)) / 2, true);  // 12.5 WAD max, 1/10m WAD min, or zero (total can't be greater than 25 WAD) (non-zero to avoid division by zero in stakeDate)
        dTime        = constrictToRange(dTime,  15, unstakeDelay / 2);                                   // Max dtime is half unstakeDelay
        dTime2       = constrictToRange(dTime2, 15, unstakeDelay / 2);                                   // Max dtime is half unstakeDelay (total less than unstakeDelay for test)

        uint256 start = block.timestamp;
        sid.setAllowlistStakeLocker(address(pool), address(che), true);
        che.approve(address(bPool), address(stakeLocker), MAX_UINT);

        che.stake(address(stakeLocker), stakeAmount);  

        assertEq(stakeLocker.balanceOf(address(che)),             stakeAmount);
        assertEq(stakeLocker.stakeDate(address(che)),                   start);
        assertEq(stakeLocker.getUnstakeableBalance(address(che)),           0);  // No time has passed

        hevm.warp(start + dTime);

        unstakeableBal.pre = stakeLocker.getUnstakeableBalance(address(che));

        assertEq(stakeLocker.balanceOf(address(che)),       stakeAmount);
        assertEq(stakeLocker.stakeDate(address(che)),             start);
        assertEq(unstakeableBal.pre, dTime * stakeAmount / unstakeDelay);  // Withdrawable balance is a linear function of dTime

        uint256 newStakeDate = getNewStakeDate(address(che), stakeAmount2);  // Calculate stake date

        che.stake(address(stakeLocker), stakeAmount2);

        unstakeableBal.post = stakeLocker.getUnstakeableBalance(address(che));

        assertEq(stakeLocker.balanceOf(address(che)), stakeAmount + stakeAmount2);
        assertEq(stakeLocker.stakeDate(address(che)),               newStakeDate);

        // Withdrawable balance should not change after stakeDate is recalculated (bptMin rounding error accounted for, test_stake_to_measure_effect_on_stake_date proves strict equality)
        withinDiff(unstakeableBal.pre, unstakeableBal.post, bptMin * 100);  

        hevm.warp(start + dTime + dTime2);

        assertEq(stakeLocker.balanceOf(address(che)), stakeAmount + stakeAmount2);
        assertEq(stakeLocker.stakeDate(address(che)),               newStakeDate);

    
        assertEq(stakeLocker.getUnstakeableBalance(address(che)), (block.timestamp - newStakeDate) * (stakeAmount + stakeAmount2) / unstakeDelay);  // Function uses total staked and stakeDate
    }

    function setUpLoanMakeOnePaymentAndDefault() public returns (uint256 interestPaid) {
        // Fund the pool
        mint("USDC", address(ali), 20_000_000 * USD);
        ali.approve(USDC, address(pool), MAX_UINT);
        ali.deposit(address(pool), 10_000_000 * USD);

        // Fund the loan
        sid.fundLoan(address(pool), address(loan), address(dlFactory), 1_000_000 * USD);
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
        sid.triggerDefault(address(pool), address(loan), address(dlFactory));
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

        stakeAmount = constrictToRange(stakeAmount,  bptMin, bPool.balanceOf(address(che)), true);  // 25 WAD max, 1/10m WAD min, or zero (min is roughly equal to 10 cents) (non-zero)

        sid.setAllowlistStakeLocker(address(pool), address(che), true);
        sid.setAllowlistStakeLocker(address(pool), address(dan), true);
        sid.setAllowlistStakeLocker(address(pool), address(eli), true);

        che.approve(address(bPool), address(stakeLocker), MAX_UINT);
        dan.approve(address(bPool), address(stakeLocker), MAX_UINT);
        eli.approve(address(bPool), address(stakeLocker), MAX_UINT);

        che.stake(address(stakeLocker), stakeAmount);  // Che stakes before default, unstakes min amount
        dan.stake(address(stakeLocker), 25 * WAD);     // Dan stakes before default, unstakes full amount

        uint256 interestPaid = setUpLoanMakeOnePaymentAndDefault();  // This does not affect any Pool accounting
        
        /*****************************************************/
        /*** Make Claim, Update StakeLocker FDT Accounting ***/
        /*****************************************************/

        // Pre-claim FDT and StakeLocker checks (Che only)
        stakeLockerBal.pre       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.pre       = stakeLocker.totalSupply();
        stakerFDTBal.pre         = stakeLocker.balanceOf(address(che));
        fundsTokenBal.pre        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.pre  = stakeLocker.withdrawableFundsOf(address(che));
        bptLosses.pre            = stakeLocker.bptLosses();
        recognizableLossesOf.pre = stakeLocker.recognizableLossesOf(address(che));

        assertEq(stakeLockerBal.pre,      stakeAmount + 75 * WAD);  // Che + Dan + Sid stake
        assertEq(fdtTotalSupply.pre,      stakeAmount + 75 * WAD);  // FDT Supply == amount staked
        assertEq(stakerFDTBal.pre,                   stakeAmount);  // Che FDT balance == amount staked
        assertEq(fundsTokenBal.pre,                            0);  // Claim hasnt been made yet - interest not realized
        assertEq(withdrawableFundsOf.pre,                      0);  // Claim hasnt been made yet - interest not realized
        assertEq(bptLosses.pre,                                0);  // Claim hasnt been made yet - losses   not realized
        assertEq(recognizableLossesOf.pre,                     0);  // Claim hasnt been made yet - losses   not realized
        
        sid.claim(address(pool), address(loan),  address(dlFactory));  // Pool Delegate claims funds, updating accounting for interest and losses from Loan

        // Post-claim FDT and StakeLocker checks (Che only)
        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(che));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(che));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(che));

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

        assertEq(bPool.balanceOf(address(che)),        25 * WAD - stakeAmount);  // Starting balance minus staked amount
        assertEq(IERC20(USDC).balanceOf(address(che)),                      0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  fundsTokenBal.pre * stakeAmount / fdtTotalSupply.pre);  // Assert FDT interest accounting
        assertEq(recognizableLossesOf.pre,     bptLosses.pre * stakeAmount / fdtTotalSupply.pre);  // Assert FDT loss     accounting

        // re-using the variable to avoid stack too deep issue.
        interestPaid = block.timestamp;

        assertTrue(      che.try_intendToUnstake(address(stakeLocker)));
        assertEq(stakeLocker.stakeCooldown(address(che)), interestPaid);
        hevm.warp(interestPaid + globals.cooldownPeriod() + 1);
        assertTrue(     !che.try_unstake(address(stakeLocker), recognizableLossesOf.pre - 1));  // Cannot withdraw less than the losses incurred
        hevm.warp(interestPaid + globals.cooldownPeriod());
        assertTrue(     !che.try_unstake(address(stakeLocker), recognizableLossesOf.pre));
        hevm.warp(interestPaid + globals.cooldownPeriod() + 1);
        assertTrue(      che.try_unstake(address(stakeLocker), recognizableLossesOf.pre));  // Withdraw lowest possible amount (amt == recognizableLosses), FDTs burned to cover losses, no BPTs left to withdraw

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(che));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(che));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(che));

        assertEq(stakeLockerBal.post,                  stakeAmount + 75 * WAD - bptLosses.pre);  // Che + Dan + Sid stake minus burned BPTs
        assertEq(fdtTotalSupply.post,       stakeAmount + 75 * WAD - recognizableLossesOf.pre);  // FDT Supply == amount staked
        assertEq(stakerFDTBal.post,                    stakeAmount - recognizableLossesOf.pre);  // Che FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                 stakingRevenue - withdrawableFundsOf.pre);  // Interest has been claimed 
        assertEq(withdrawableFundsOf.post,                                                  0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                     bptLosses.pre - recognizableLossesOf.pre);  // Losses accounting has been updated
        assertEq(recognizableLossesOf.post,                                                 0);  // Losses have been recognized

        assertEq(bPool.balanceOf(address(che)),         25 * WAD - stakeAmount);  // Starting balance minus staked amount (same as before unstake, meaning no BPTs were returned to Che)
        assertEq(IERC20(USDC).balanceOf(address(che)), withdrawableFundsOf.pre);  // USDC balance

        /******************************************************/
        /*** Staker Post-Loss Unstake Accounting (Dan Only) ***/
        /******************************************************/

        uint256 initialFundsTokenBal = fundsTokenBal.pre;  // Need this for asserting pre-unstake FDT
        uint256 initialLosses        = bptLosses.pre;      // Need this for asserting pre-unstake FDT

        // Pre-unstake FDT and StakeLocker checks (update variables)
        stakeLockerBal.pre       = stakeLockerBal.post;
        fdtTotalSupply.pre       = fdtTotalSupply.post;
        stakerFDTBal.pre         = stakeLocker.balanceOf(address(dan));
        fundsTokenBal.pre        = fundsTokenBal.post;
        withdrawableFundsOf.pre  = stakeLocker.withdrawableFundsOf(address(dan));
        bptLosses.pre            = bptLosses.post;  
        recognizableLossesOf.pre = stakeLocker.recognizableLossesOf(address(dan));

        assertEq(bPool.balanceOf(address(dan)),        0);  // Staked entire balance
        assertEq(IERC20(USDC).balanceOf(address(dan)), 0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  initialFundsTokenBal * 25 * WAD / (75 * WAD + stakeAmount));  // Assert FDT interest accounting (have to use manual totalSupply because of Che unstake)
        assertEq(recognizableLossesOf.pre,        initialLosses * 25 * WAD / (75 * WAD + stakeAmount));  // Assert FDT loss     accounting (have to use manual totalSupply because of Che unstake)

        interestPaid = block.timestamp;

        assertTrue(      dan.try_intendToUnstake(address(stakeLocker)));
        assertEq(stakeLocker.stakeCooldown(address(dan)), interestPaid);
        hevm.warp(interestPaid + globals.cooldownPeriod() + 1);
        assertTrue(     !dan.try_unstake(address(stakeLocker), stakerFDTBal.pre + 1));  // Cannot withdraw more than current FDT bal
        assertTrue(      dan.try_unstake(address(stakeLocker), stakerFDTBal.pre));      // Withdraw remaining BPTs

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(dan));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(dan));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(dan));

        assertEq(stakeLockerBal.post,      stakeLockerBal.pre - (25 * WAD - recognizableLossesOf.pre));  // Dan's unstake amount minus his losses
        assertEq(fdtTotalSupply.post,                                   fdtTotalSupply.pre - 25 * WAD);  // FDT Supply = previous FDT total supply - unstake amount
        assertEq(stakerFDTBal.post,                                                                 0);  // Dan's entire FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                      fundsTokenBal.pre - withdrawableFundsOf.pre);  // Interest has been claimed 
        assertEq(withdrawableFundsOf.post,                                                          0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                             bptLosses.pre - recognizableLossesOf.pre);  // Losses accounting has been updated
        assertEq(recognizableLossesOf.post,                                                         0);  // Losses have been recognized

        assertEq(bPool.balanceOf(address(dan)),        25 * WAD - recognizableLossesOf.pre);  // Starting balance minus losses
        assertEq(IERC20(USDC).balanceOf(address(dan)),             withdrawableFundsOf.pre);  // USDC balance from interest

        /************************************************************/
        /*** Post-Loss Staker Stake/Unstake Accounting (Eli Only) ***/
        /************************************************************/
        // Ensure that Eli has no loss exposure if he stakes after a default has already occured
        uint256 eliStakeAmount = bPool.balanceOf(address(dan));
        dan.transfer(address(bPool), address(eli), eliStakeAmount);  // Dan sends Eli a balance of BPTs so he can stake

        eli.stake(address(stakeLocker), eliStakeAmount);

        // Pre-unstake FDT and StakeLocker checks (update variables)
        stakeLockerBal.pre       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.pre       = stakeLocker.totalSupply();
        stakerFDTBal.pre         = stakeLocker.balanceOf(address(eli));
        fundsTokenBal.pre        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.pre  = stakeLocker.withdrawableFundsOf(address(eli));
        bptLosses.pre            = stakeLocker.bptLosses();
        recognizableLossesOf.pre = stakeLocker.recognizableLossesOf(address(eli));

        assertEq(bPool.balanceOf(address(eli)),        0);  // Staked entire balance
        assertEq(IERC20(USDC).balanceOf(address(eli)), 0);  // USDC balance

        assertEq(withdrawableFundsOf.pre,  0);  // Assert FDT interest accounting
        assertEq(recognizableLossesOf.pre, 0);  // Assert FDT loss     accounting

        assertTrue(eli.try_intendToUnstake(address(stakeLocker)));
        hevm.warp(block.timestamp + globals.unstakeDelay());
        eli.unstake(address(stakeLocker), eliStakeAmount);  // Unstake entire balance

        stakeLockerBal.post       = bPool.balanceOf(address(stakeLocker));
        fdtTotalSupply.post       = stakeLocker.totalSupply();
        stakerFDTBal.post         = stakeLocker.balanceOf(address(eli));
        fundsTokenBal.post        = IERC20(USDC).balanceOf(address(stakeLocker));
        withdrawableFundsOf.post  = stakeLocker.withdrawableFundsOf(address(eli));
        bptLosses.post            = stakeLocker.bptLosses();
        recognizableLossesOf.post = stakeLocker.recognizableLossesOf(address(eli));

        assertEq(stakeLockerBal.post,      stakeLockerBal.pre - eliStakeAmount);  // Eli recovered full stake
        assertEq(fdtTotalSupply.post,      fdtTotalSupply.pre - eliStakeAmount);  // FDT Supply minus Eli's full stake
        assertEq(stakerFDTBal.post,                                          0);  // Eli FDT balance burned on withdraw
        assertEq(fundsTokenBal.post,                         fundsTokenBal.pre);  // No interest has been claimed 
        assertEq(withdrawableFundsOf.post,                                   0);  // Interest cannot be claimed twice
        assertEq(bptLosses.post,                                 bptLosses.pre);  // Losses accounting has not changed
        assertEq(recognizableLossesOf.post,                                  0);  // Losses have been "recognized" (there were none)

        assertEq(bPool.balanceOf(address(eli)),        eliStakeAmount);  // Eli recovered full stake
        assertEq(IERC20(USDC).balanceOf(address(eli)),              0);  // USDC balance from interest (none)
    }
} 
