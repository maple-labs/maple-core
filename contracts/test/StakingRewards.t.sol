pragma solidity >=0.6.11;

import "./TestUtil.sol";

import "./user/Farmer.sol";
import "./user/Governor.sol";
import "./user/PoolDelegate.sol";

import "../DebtLockerFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../MapleToken.sol";
import "../Pool.sol";
import "../PoolFactory.sol";
import "../StakeLockerFactory.sol";

contract StakingRewardsTest is TestUtil {

    Farmer                            ali;
    Farmer                            bob;
    Farmer                            che;
    Governor                          gov;
    Governor                      fakeGov;
    PoolDelegate                      sid;

    DebtLockerFactory           dlFactory;
    LiquidityLockerFactory      llFactory;
    MapleGlobals                  globals;
    MapleToken                        mpl;
    PoolFactory               poolFactory;
    Pool                             pool;
    StakeLockerFactory          slFactory;
    
    IBPool                          bPool;

    StakingRewards         stakingRewards;

    uint256 constant public MAX_UINT = uint(-1);

    function setUp() public {

        ali     = new Farmer(stakingRewards, pool);  // Actor: Yield farmer
        bob     = new Farmer(stakingRewards, pool);  // Actor: Yield farmer
        che     = new Farmer(stakingRewards, pool);  // Actor: Yield farmer
        gov     = new Governor();                    // Actor: Governor of Maple.
        fakeGov = new Governor();                    // Actor: Governor of Maple.
        sid     = new PoolDelegate();                // Actor: Manager of the Pool.

        mpl         = new MapleToken("MapleToken", "MAPL", USDC);
        globals     = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        slFactory   = new StakeLockerFactory();                        // Setup the SL factory to facilitate Pool factory functionality.
        llFactory   = new LiquidityLockerFactory();                    // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory = new PoolFactory(address(globals));               // Create pool factory.
        dlFactory   = new DebtLockerFactory();   

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);
        gov.setPoolDelegateWhitelist(address(sid),                       true);

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * USD);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool),          MAX_UINT);

        bPool.bind(USDC,         50_000_000 * USD, 5 ether);  // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl),    100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight
        bPool.finalize();
        bPool.transfer(address(sid), bPool.balanceOf(address(this)) / 2);

        gov.setLoanAsset(USDC, true);
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

        address stakeLocker = pool.stakeLocker();
        sid.approve(address(bPool), stakeLocker, uint(-1));
        sid.stake(stakeLocker, bPool.balanceOf(address(sid))); // Stake all BPTs against pool through stakeLocker
        sid.finalize(address(pool));

        // Create new staking rewards contract with MPL rewards and Pool FDTs as the stake token
        stakingRewards = gov.createStakingRewards(address(mpl), address(pool)); 

        fakeGov.setGovStakingRewards(stakingRewards); // Used to assert failures 

        ali = new Farmer(stakingRewards, pool);
        bob = new Farmer(stakingRewards, pool);
        che = new Farmer(stakingRewards, pool);

        mint("USDC", address(ali), 1000 * USD);
        mint("USDC", address(bob), 1000 * USD);
        mint("USDC", address(che), 1000 * USD);

        ali.approve(USDC, address(pool), MAX_UINT);
        bob.approve(USDC, address(pool), MAX_UINT);
        che.approve(USDC, address(pool), MAX_UINT);

        ali.deposit(address(pool), 1000 * USD);  // Mints 1000 ether of Pool FDT tokens
        bob.deposit(address(pool), 1000 * USD);  // Mints 1000 ether of Pool FDT tokens
        che.deposit(address(pool), 1000 * USD);  // Mints 1000 ether of Pool FDT tokens
    }

    /*******************************/
    /*** Admin functions testing ***/
    /*******************************/
    function test_notifyRewardAmount() public {
        assertEq(stakingRewards.periodFinish(),              0);
        assertEq(stakingRewards.rewardRate(),                0);
        assertEq(stakingRewards.rewardsDuration(),      7 days);  // Pre set value
        assertEq(stakingRewards.lastUpdateTime(),            0);  
        assertEq(stakingRewards.rewardPerTokenStored(),      0); 

        mpl.transfer(address(stakingRewards), 60_000 ether); // 60k MPL per week => 3.12m MPL per year

        assertTrue(!fakeGov.try_notifyRewardAmount(60_000 ether));
        assertTrue(     gov.try_notifyRewardAmount(60_000 ether));

        assertEq(stakingRewards.rewardRate(),     uint256(60_000 ether) / 7 days);
        assertEq(stakingRewards.lastUpdateTime(),                block.timestamp);
        assertEq(stakingRewards.periodFinish(),         block.timestamp + 7 days);
    }

    function test_updatePeriodFinish() public {
        assertEq(stakingRewards.periodFinish(), 0);

        assertTrue(!fakeGov.try_updatePeriodFinish(block.timestamp + 30 days));
        assertTrue(     gov.try_updatePeriodFinish(block.timestamp + 30 days));

        assertEq(stakingRewards.periodFinish(), block.timestamp + 30 days);
    }

    function test_recoverERC20() public {
        mint("USDC", address(ali), 1000 * USD);

        assertEq(IERC20(USDC).balanceOf(address(ali)),            1000 * USD);
        assertEq(IERC20(USDC).balanceOf(address(gov)),                     0);
        assertEq(IERC20(USDC).balanceOf(address(stakingRewards)),          0);
        assertEq(stakingRewards.balanceOf(address(ali)),                   0);
        assertEq(stakingRewards.totalSupply(),                             0);
        
        ali.transfer(USDC, address(stakingRewards), 1000 * USD); // Ali transfers USDC directly into Staking rewards
        
        assertEq(IERC20(USDC).balanceOf(address(ali)),                     0);
        assertEq(IERC20(USDC).balanceOf(address(gov)),                     0);
        assertEq(IERC20(USDC).balanceOf(address(stakingRewards)), 1000 * USD);
        assertEq(stakingRewards.balanceOf(address(ali)),                   0);
        assertEq(stakingRewards.totalSupply(),                             0);

        assertTrue(!fakeGov.try_recoverERC20(USDC, 400 * USD));
        assertTrue(     gov.try_recoverERC20(USDC, 400 * USD));

        assertEq(IERC20(USDC).balanceOf(address(ali)),                     0);
        assertEq(IERC20(USDC).balanceOf(address(gov)),             400 * USD);
        assertEq(IERC20(USDC).balanceOf(address(stakingRewards)),  600 * USD);
        assertEq(stakingRewards.balanceOf(address(ali)),                   0);
        assertEq(stakingRewards.totalSupply(),                             0);

        assertTrue(!fakeGov.try_recoverERC20(USDC, 600 * USD));
        assertTrue(     gov.try_recoverERC20(USDC, 600 * USD));

        assertEq(IERC20(USDC).balanceOf(address(ali)),                     0);
        assertEq(IERC20(USDC).balanceOf(address(gov)),            1000 * USD);
        assertEq(IERC20(USDC).balanceOf(address(stakingRewards)),          0);
        assertEq(stakingRewards.balanceOf(address(ali)),                   0);
        assertEq(stakingRewards.totalSupply(),                             0);
    }

    function test_setRewardsDuration() public {
        assertEq(stakingRewards.periodFinish(),         0);
        assertEq(stakingRewards.rewardsDuration(), 7 days);

        mpl.transfer(address(stakingRewards), 60_000 ether); // 60k MPL per week => 3.12m MPL per year

        gov.notifyRewardAmount(60_000 ether);

        assertEq(stakingRewards.periodFinish(),    block.timestamp + 7 days);
        assertEq(stakingRewards.rewardsDuration(),                   7 days);

        assertTrue(!fakeGov.try_setRewardsDuration(30 days));
        assertTrue(    !gov.try_setRewardsDuration(30 days)); // Won't work because current rewards period hasn't ended

        hevm.warp(stakingRewards.periodFinish());

        assertTrue(!gov.try_setRewardsDuration(30 days)); // Won't work because current rewards period hasn't ended

        hevm.warp(stakingRewards.periodFinish() + 1);

        assertTrue(gov.try_setRewardsDuration(30 days)); // Works because current rewards period has ended

        assertEq(stakingRewards.rewardsDuration(), 30 days);
    }

    function test_setPaused() public {
        assertTrue(!stakingRewards.paused());

        // Ali can stake
        ali.approve(address(stakingRewards), 100 ether);
        assertTrue(ali.try_stake(100 ether));             

        // Set to paused
        assertTrue(!fakeGov.try_setPaused(true));
        assertTrue(     gov.try_setPaused(true));

        assertTrue(stakingRewards.paused());

        // Bob can't stake
        bob.approve(address(stakingRewards), 100 ether);
        assertTrue(!bob.try_stake(100 ether));

        // Ali can withdraw
        ali.approve(address(stakingRewards), 100 ether);
        assertTrue(ali.try_withdraw(100 ether));

        // Set to unpaused
        assertTrue(!fakeGov.try_setPaused(false));
        assertTrue(     gov.try_setPaused(false));

        assertTrue(!stakingRewards.paused());

        // Bob can stake
        bob.approve(address(stakingRewards), 100 ether);
        assertTrue(bob.try_stake(100 ether));

    }

    /****************************/
    /*** LP functions testing ***/
    /****************************/
    function test_stake() public {
        assertEq(pool.balanceOf(address(ali)), 1000 ether);
        assertEq(stakingRewards.balanceOf(address(ali)),                 0);
        assertEq(stakingRewards.totalSupply(),                           0);

        assertTrue(!ali.try_stake(100 ether));  // Can't stake before approval

        ali.approve(address(stakingRewards), 100 ether);

        assertTrue(!ali.try_stake(0));          // Can't stake zero
        assertTrue( ali.try_stake(100 ether));  // Can stake after approval

        assertEq(pool.balanceOf(address(ali)), 900 ether);
        assertEq(stakingRewards.balanceOf(address(ali)),        100 ether);
        assertEq(stakingRewards.totalSupply(),                  100 ether);
    }

    function test_withdraw() public {
        ali.approve(address(stakingRewards), 100 ether);
        ali.stake(100 ether);

        assertEq(pool.balanceOf(address(ali)), 900 ether);
        assertEq(stakingRewards.balanceOf(address(ali)),        100 ether);
        assertEq(stakingRewards.totalSupply(),                  100 ether);

        assertTrue(!ali.try_withdraw(0));          // Can't withdraw zero
        assertTrue( ali.try_withdraw(100 ether));  // Can withdraw 

        assertEq(pool.balanceOf(address(ali)), 1000 ether);
        assertEq(stakingRewards.balanceOf(address(ali)),                 0);
        assertEq(stakingRewards.totalSupply(),                           0);
    }

    function assertRewardsAccounting(
        address user,
        uint256 totalSupply,
        uint256 rewardPerTokenStored, 
        uint256 userRewardPerTokenPaid, 
        uint256 earned, 
        uint256 rewards, 
        uint256 rewardTokenBal
    ) 
        public 
    {
        assertEq(stakingRewards.totalSupply(),                totalSupply);
        assertEq(stakingRewards.rewardPerTokenStored(),       rewardPerTokenStored);
        assertEq(stakingRewards.userRewardPerTokenPaid(user), userRewardPerTokenPaid);
        assertEq(stakingRewards.earned(user),                 earned);
        assertEq(stakingRewards.rewards(user),                rewards);
        assertEq(mpl.balanceOf(user),                         rewardTokenBal);
    }

    /**********************************/
    /*** Rewards accounting testing ***/
    /**********************************/
    function test_rewards_single_epoch() public {
        ali.approve(address(stakingRewards), 100 ether);
        bob.approve(address(stakingRewards), 100 ether);
        ali.stake(10 ether);

        mpl.transfer(address(stakingRewards), 60_000 ether);  // 60k MPL per week => 3.12m MPL per year

        gov.notifyRewardAmount(60_000 ether);

        uint256 rewardRate = stakingRewards.rewardRate();
        uint256 start      = block.timestamp;

        /*** Ali time = 0 post-stake ***/
        assertRewardsAccounting({
            user:                   address(ali),  // User accounting for
            totalSupply:            10 ether,      // Ali's stake
            rewardPerTokenStored:   0,             // Starting state
            userRewardPerTokenPaid: 0,             // Starting state
            earned:                 0,             // Starting state
            rewards:                0,             // Starting state
            rewardTokenBal:         0              // Starting state
        });

        ali.getReward();  // Get reward at time = 0

        /*** Ali time = (0 days) post-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),  // User accounting for
            totalSupply:            10 ether,      // Ali's stake
            rewardPerTokenStored:   0,             // Starting state (getReward has no effect at time = 0)
            userRewardPerTokenPaid: 0,             // Starting state (getReward has no effect at time = 0)
            earned:                 0,             // Starting state (getReward has no effect at time = 0)
            rewards:                0,             // Starting state (getReward has no effect at time = 0)
            rewardTokenBal:         0              // Starting state (getReward has no effect at time = 0)
        });

        hevm.warp(start + 1 days);  // Warp to time = (1 days) (dTime = 1 days)

        uint256 dTime_1_rpt = rewardRate * 1 days * WAD / 10 ether;  // Reward per token (RPT) that was used before bob entered the pool (accrued over dTime = 1 days)

        /*** Ali time = (1 days) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),                  // User accounting for
            totalSupply:            10 ether,                      // Ali's stake
            rewardPerTokenStored:   0,                             // Not updated yet
            userRewardPerTokenPaid: 0,                             // Not updated yet
            earned:                 dTime_1_rpt * 10 ether / WAD,  // Time-based calculation
            rewards:                0,                             // Not updated yet
            rewardTokenBal:         0                              // Nothing claimed
        });

        ali.getReward();  // Get reward at time = (1 days) 

        /*** Ali time = (1 days) post-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),                 // User accounting for
            totalSupply:            10 ether,                     // Ali's stake
            rewardPerTokenStored:   dTime_1_rpt,                  // Updated on updateReward
            userRewardPerTokenPaid: dTime_1_rpt,                  // Updated on updateReward for 100% ownership in pool after 1hr
            earned:                 0,                            // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                            // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         dTime_1_rpt * 10 ether / WAD  // Updated on getReward, user has claimed rewards (equal to original earned() amt at this timestamp))
        });

        bob.stake(10 ether); // Bob stakes 10 ether, giving him 50% stake in the pool rewards going forward

        /*** Bob time = (1 days) post-stake ***/
        assertRewardsAccounting({
            user:                   address(bob),  // User accounting for
            totalSupply:            20 ether,      // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt,   // Updated on updateReward (value is halved due to totalSupply)
            userRewardPerTokenPaid: dTime_1_rpt,   // Updated on updateReward, prevents bob from claiming past rewards
            earned:                 0,             // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,             // Not updated yet
            rewardTokenBal:         0              // Not updated yet
        });

        hevm.warp(start + 2 days);  // Warp to time = (2 days) (dTime = 1 days)

        uint256 dTime_2_rpt = rewardRate * 1 days * WAD / 20 ether;  // Reward per token (RPT) that was used after  bob entered the pool (accrued over dTime = 1 days, on second day)

        /*** Ali time = (2 days) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),                  // User accounting for
            totalSupply:            20 ether,                      // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt,                   // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt,                   // Used so Ali can't do multiple claims
            earned:                 dTime_2_rpt * 10 ether / WAD,  // Ali has not claimed any rewards that have accrued during day 2
            rewards:                0,                             // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         dTime_1_rpt * 10 ether / WAD   // From previous claim
        });

        /*** Bob time = (2 days) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(bob),                  // User accounting for
            totalSupply:            20 ether,                      // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt,                   // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt,                   // Used so Bob can't do claims on past rewards
            earned:                 dTime_2_rpt * 10 ether / WAD,  // Bob has not claimed any rewards that have accrued during day 2
            rewards:                0,                             // Not updated yet
            rewardTokenBal:         0                              // Not updated yet
        });

        bob.stake(20 ether); // Bob stakes another 20 ether, giving him 75% stake in the pool rewards going forward

        /*** Bob time = (2 days) post-stake ***/
        assertRewardsAccounting({
            user:                   address(bob),                  // User accounting for
            totalSupply:            40 ether,                      // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt,     // Updated on stake to snapshot rewardPerToken up to that point
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt,     // Used so Bob can't do claims on past rewards
            earned:                 dTime_2_rpt * 10 ether / WAD,  // Earned updated to reflect all unclaimed earnings pre stake
            rewards:                dTime_2_rpt * 10 ether / WAD,  // Rewards updated to earnings on updateReward
            rewardTokenBal:         0                              // Not updated yet
        });

        hevm.warp(start + 2 days + 1 hours);  // Warp to time = (2 days + 1 hours) (dTime = 1 hours)

        uint256 dTime_3_rpt = rewardRate * 1 hours * WAD / 40 ether;  // Reward per token (RPT) that was used after bob staked more into the pool (accrued over dTime = 1 hours)

        /*** Ali time = (2 days + 1 hours) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),                                  // User accounting for
            totalSupply:            40 ether,                                      // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt,                     // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt,                                   // Used so Ali can't do multiple claims
            earned:                 (dTime_2_rpt + dTime_3_rpt) * 10 ether / WAD,  // Ali has not claimed any rewards that have accrued during day 2
            rewards:                0,                                             // Not updated yet
            rewardTokenBal:         dTime_1_rpt * 10 ether / WAD                   // From previous claim
        });

        /*** Bob time = (2 days + 1 hours) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(bob),                                             // User accounting for
            totalSupply:            40 ether,                                                 // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt,                                // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt,                                // Used so Bob can't do claims on past rewards
            earned:                 (dTime_2_rpt * 10 ether + dTime_3_rpt * 30 ether) / WAD,  // Bob's earnings since he entered the pool
            rewards:                dTime_2_rpt * 10 ether / WAD,                             // Rewards updated to reflect all unclaimed earnings pre stake
            rewardTokenBal:         0                                                         // Not updated yet
        });

        bob.getReward();  // Get reward at time = (2 days + 1 hours)

        /*** Bob time = (2 days + 1 hours) post-claim ***/
        assertRewardsAccounting({
            user:                   address(bob),                                            // User accounting for
            totalSupply:            40 ether,                                                // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Updated on updateReward
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Used so Bob can't do multiple claims
            earned:                 0,                                                       // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                       // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime_2_rpt * 10 ether + dTime_3_rpt * 30 ether) / WAD  // Updated on getReward, user has claimed rewards (equal to original earned() amt at this timestamp))
        });

        bob.getReward();  // Try double claim

        /*** Bob time = (2 days + 1 hours) post-claim (ASSERT NOTHING CHANGES) ***/
        assertRewardsAccounting({
            user:                   address(bob),                                            // User accounting for
            totalSupply:            40 ether,                                                // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Updated on updateReward
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Used so Bob can't do multiple claims
            earned:                 0,                                                       // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                       // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime_2_rpt * 10 ether + dTime_3_rpt * 30 ether) / WAD  // Updated on getReward, user has claimed rewards (equal to original earned() amt at this timestamp))
        });

        ali.withdraw(5 ether);  // Ali withdraws 5 ether at time = (2 days + 1 hours)

        /*** Ali time = (2 days) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),                                  // User accounting for
            totalSupply:            35 ether,                                      // Ali + Bob stake, lower now that Ali withdrew
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,       // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,       // Used so Ali can't claim past earnings
            earned:                 (dTime_2_rpt + dTime_3_rpt) * 10 ether / WAD,  // Ali has not claimed any rewards that have accrued during dTime2 and dTime3
            rewards:                (dTime_2_rpt + dTime_3_rpt) * 10 ether / WAD,  // Updated on updateReward to earned()
            rewardTokenBal:         dTime_1_rpt * 10 ether / WAD                   // From previous claim
        });

        hevm.warp(start + 3 days + 1 hours);  // Warp to time = (3 days + 1 hours) (dTime = 1 days)

        uint256 dTime_4_rpt = rewardRate * 1 days * WAD / 35 ether;  // Reward per token (RPT) that was used after ali withdrew from the pool (accrued over dTime = 1 days)

        /*** Ali time = (3 days + 1 hours) pre-exit ***/
        assertRewardsAccounting({
            user:                     address(ali),                             // User accounting for
            totalSupply:              35 ether,                                 // Ali + Bob stake 
            rewardPerTokenStored:     dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,  // Not updated yet
            userRewardPerTokenPaid:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,  // Used so Ali can't do multiple claims
            earned:                 ((dTime_2_rpt + dTime_3_rpt) * 10 ether + dTime_4_rpt * 5 ether) / WAD,            // Ali has not claimed any rewards that have accrued during dTime4
            rewards:                 (dTime_2_rpt + dTime_3_rpt) * 10 ether / WAD,                                       // Not updated yet
            rewardTokenBal:           dTime_1_rpt * 10 ether / WAD              // From previous claim
        });

        /*** Bob time = (2 days + 1 hours) pre-exit ***/
        assertRewardsAccounting({
            user:                   address(bob),                                            // User accounting for
            totalSupply:            35 ether,                                                // Ali + Bob stake 
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Used so Bob can't do multiple claims
            earned:                 dTime_4_rpt * 30 ether / WAD,                            // Bob has not claimed any rewards that have accrued during dTime4
            rewards:                0,                                                       // Not updated yet
            rewardTokenBal:         (dTime_2_rpt * 10 ether + dTime_3_rpt * 30 ether) / WAD  // From previous claim
        });

        ali.exit();  // Ali exits 5 ether  at time = (3 days + 1 hours)
        bob.exit();  // Bob exits 20 ether at time = (3 days + 1 hours)

        /*** Ali time = (3 days + 1 hours) post-exit ***/
        assertRewardsAccounting({
            user:                   address(ali),                                                                         // User accounting for
            totalSupply:            0,                                                                                    // Ali + Bob withdrew all stake
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt + dTime_4_rpt,                                // Updated on updateReward
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt + dTime_4_rpt,                                // Used so Ali can't do multiple claims
            earned:                 0,                                                                                    // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                                                    // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         ((dTime_1_rpt + dTime_2_rpt + dTime_3_rpt) * 10 ether + dTime_4_rpt * 5 ether) / WAD  // Total earnings from pool
        });

        /*** Bob time = (2 days + 1 hours) post-exit ***/
        assertRewardsAccounting({
            user:                   address(bob),                                                            // User accounting for
            totalSupply:            0,                                                                       // Ali + Bob withdrew all stake
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt + dTime_4_rpt,                   // Updated on updateReward
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt + dTime_4_rpt,                   // Used so Bob can't do multiple claims
            earned:                 0,                                                                       // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                                       // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime_2_rpt * 10 ether + (dTime_3_rpt + dTime_4_rpt) * 30 ether) / WAD  // Total earnings from pool
        });
    }
}
