// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Borrower.sol";
import "./user/Governor.sol";
import "./user/LP.sol";
import "./user/PoolDelegate.sol";
import "./user/Staker.sol";

import "../interfaces/IBFactory.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IStakeLocker.sol";

import "../BulletRepaymentCalc.sol";
import "../CollateralLockerFactory.sol";
import "../DebtLocker.sol";
import "../DebtLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LateFeeCalc.sol";
import "../LiquidityLockerFactory.sol";
import "../Loan.sol";
import "../LoanFactory.sol";
import "../MapleToken.sol";
import "../Pool.sol";
import "../PoolFactory.sol";
import "../PremiumCalc.sol";
import "../StakeLockerFactory.sol";

import "../oracles/ChainlinkOracle.sol";

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

    BulletRepaymentCalc             bulletCalc;
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
    ChainlinkOracle                  usdOracle;

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

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        flFactory      = new FundingLockerFactory();                                    // Setup the FL factory to facilitate Loan factory functionality.
        clFactory      = new CollateralLockerFactory();                                 // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory    = new LoanFactory(address(globals));                             // Create Loan factory.
        slFactory      = new StakeLockerFactory();                                      // Setup the SL factory to facilitate Pool factory functionality.
        llFactory      = new LiquidityLockerFactory();                                  // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory    = new PoolFactory(address(globals));                             // Create pool factory.
        dlFactory      = new DebtLockerFactory();                                       // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        bulletCalc     = new BulletRepaymentCalc();                                     // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                                            // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);                                          // Flat 5% premium
        trs            = new Treasury();                                                // Treasury.

        gov.setValidLoanFactory(address(loanFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);

        wethOracle = new ChainlinkOracle(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, WBTC, address(this));
        usdOracle  = new ChainlinkOracle(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9, USDC, address(this));
        
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

        gov.setPoolDelegateWhitelist(address(sid), true);
        gov.setMapleTreasury(address(trs));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), 50 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(che), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
        bPool.transfer(address(dan), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool

        // Set Globals
        gov.setCalc(address(bulletCalc),  true);
        gov.setCalc(address(lateFeeCalc), true);
        gov.setCalc(address(premiumCalc), true);
        gov.setCollateralAsset(WETH, true);
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

        stakeLocker = IStakeLocker(pool.stakeLocker());

        // loan Specifications
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        // Stake and finalize pool
        sid.approve(address(bPool), address(stakeLocker), 50 * WAD);
        sid.stake(address(stakeLocker), 50 * WAD);
        sid.finalize(address(pool));  // PD that staked can finalize

        assertEq(uint256(pool.poolState()), 1);  // Finalize
    }

    function test_stake_to_measure_effect_on_stake_date() external {
        uint256 currentDate = block.timestamp;

        sid.setWhitelistStakeLocker(address(pool), address(che), true);
        sid.setWhitelistStakeLocker(address(pool), address(dan), true);
        che.approve(address(bPool), address(stakeLocker), uint256(-1));
        dan.approve(address(bPool), address(stakeLocker), uint256(-1));

        assert_for_stake(address(che), 25 * WAD, 50 * WAD, 50 * WAD, 0, 0);
        assert_for_stake(address(dan), 25 * WAD, 50 * WAD, 50 * WAD, 0, 0);

        assertTrue(che.try_stake(address(stakeLocker), 5 * WAD)); 
        assert_for_stake(address(che), 20 * WAD, 55 * WAD, 55 * WAD, 5 * WAD, currentDate);
        assertEq(stakeLocker.getUnstakeableBalance(address(che)), 0);

        currentDate = currentDate + 1 days;
        hevm.warp(currentDate);

        assertTrue(dan.try_stake(address(stakeLocker), 4 * WAD));
        assert_for_stake(address(dan), 21 * WAD, 59 * WAD, 59 * WAD, 4 * WAD, currentDate);
        assertEq(stakeLocker.getUnstakeableBalance(address(dan)), 0);

        uint256 oldStakeDate = stakeLocker.stakeDate(address(che));
        uint256 newStakeDate = get_new_stake_date(address(che), 5 * WAD);

        uint256 che_unstakeableBal_before = stakeLocker.getUnstakeableBalance(address(che));
        assertEq(che_unstakeableBal_before, 55555555555555555);

        assertTrue(che.try_stake(address(stakeLocker), 5 * WAD)); 

        uint256 che_unstakeableBal_after = stakeLocker.getUnstakeableBalance(address(che));
        assertEq(che_unstakeableBal_after, 55555555555555550);

        assert_for_stake(address(che), 15 * WAD, 64 * WAD, 64 * WAD, 10 * WAD, newStakeDate);
        assertEq(newStakeDate - oldStakeDate, 12 hours);  // coef will be 0.5 days.

        currentDate = currentDate + 5 days;
        hevm.warp(currentDate);

        oldStakeDate = stakeLocker.stakeDate(address(dan));
        newStakeDate = get_new_stake_date(address(dan), 16 * WAD);
        assertTrue(dan.try_stake(address(stakeLocker), 16 * WAD));
        assert_for_stake(address(dan), 5 * WAD, 80 * WAD, 80 * WAD, 20 * WAD, newStakeDate);
        assertEq(newStakeDate - oldStakeDate, 96 hours);  // coef will be 0.8 days. 4 days
    }

    function get_new_stake_date(address who, uint256 amt) public returns(uint256 newStakeDate) {
        uint256 stkDate = stakeLocker.stakeDate(who);
        uint256 coef = (WAD * amt) / (stakeLocker.balanceOf(who) + amt);
        newStakeDate = stkDate + (((now - stkDate) * coef) / WAD);
    }

    function assert_for_stake(address staker, uint256 staker_bPoolBal, uint256 sl_bPoolBal, uint256 sl_totalSupply, uint256 staker_slBal, uint256 staker_slStakeDate) public {
        assertEq(bPool.balanceOf(staker),                staker_bPoolBal,     "Incorrect balance of staker");
        assertEq(bPool.balanceOf(address(stakeLocker)),  sl_bPoolBal,         "Incorrect balance of stake locker");
        assertEq(stakeLocker.totalSupply(),              sl_totalSupply,      "Incorrect total supply of stake locker");
        assertEq(stakeLocker.balanceOf(staker),          staker_slBal,        "Incorrect balance of staker for stake locker");
        assertEq(stakeLocker.stakeDate(staker),          staker_slStakeDate,  "Incorrect stake date for staker");
    }

    function test_stake() public {
        uint256 startDate = block.timestamp;

        assertTrue(!che.try_stake(address(stakeLocker),   25 * WAD));  // Hasn't approved BPTs
        che.approve(address(bPool), address(stakeLocker), 25 * WAD);

        assertTrue(!che.try_stake(address(stakeLocker),   25 * WAD));  // Isn't yet whitelisted
        che.approve(address(bPool), address(stakeLocker), 25 * WAD);

        sid.setWhitelistStakeLocker(address(pool), address(che), true);

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

    function test_stake_transfer_restrictions() public {

        sid.setWhitelistStakeLocker(address(pool), address(che), true); // Add Staker to whitelist

        // transfer() checks

        che.approve(address(bPool), address(stakeLocker), 25 * WAD); // Stake tokens
        assertTrue(che.try_stake(address(stakeLocker), 25 * WAD));

        assertTrue(!che.try_transfer(address(stakeLocker), address(ali), 1 * WAD)); // No transfer to non-whitelisted user

        sid.setWhitelistStakeLocker(address(pool), address(ali), true); // Add ali to whitelist

        assertTrue(che.try_transfer(address(stakeLocker), address(ali), 1 * WAD)); // Yes transfer to whitelisted user

        assertTrue(che.try_transfer(address(stakeLocker), address(sid), 1 * WAD)); // Yes transfer to pool delegate

        // transferFrom() checks
        che.approve(address(stakeLocker), address(dan), 5 * WAD);
        sid.setWhitelistStakeLocker(address(pool), address(ali), false); // Remove ali to whitelist
        sid.setWhitelistStakeLocker(address(pool), address(dan), true); // Add dan to whitelist

        assertTrue(!dan.try_transferFrom(address(stakeLocker), address(che), address(ali), 1 * WAD)); // No transferFrom to non-whitelisted user
        assertTrue(dan.try_transferFrom(address(stakeLocker), address(che), address(dan), 1 * WAD)); // Yes transferFrom to whitelisted user
        assertTrue(dan.try_transferFrom(address(stakeLocker), address(che), address(sid), 1 * WAD)); // Yes transferFrom to pool delegate

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
        uint256 stakeDate    = block.timestamp;

        sid.setWhitelistStakeLocker(address(pool), address(che), true);
        che.approve(address(bPool), address(stakeLocker), 25 * WAD);
        che.stake(address(stakeLocker), 25 * WAD);  

        assertEq(IERC20(USDC).balanceOf(address(che)),          0);
        assertEq(bPool.balanceOf(address(che)),                 0);
        assertEq(bPool.balanceOf(address(stakeLocker)),  75 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),              75 * WAD);
        assertEq(stakeLocker.balanceOf(address(che)),    25 * WAD);
        assertEq(stakeLocker.stakeDate(address(che)),   stakeDate);

        setUpLoanAndRepay();
        hevm.warp(stakeDate + globals.unstakeDelay());

        uint256 totalStakerEarnings    = IERC20(USDC).balanceOf(address(stakeLocker));
        uint256 cheStakerEarnings_FDT  = stakeLocker.withdrawableFundsOf(address(che));
        uint256 cheStakerEarnings_calc = totalStakerEarnings * (25 * WAD) / (75 * WAD);  // Che's portion of staker earnings

        che.unstake(address(stakeLocker), 25 * WAD);  // Staker unstakes all BPTs

        withinPrecision(cheStakerEarnings_FDT, cheStakerEarnings_calc, 9);

        assertEq(IERC20(USDC).balanceOf(address(che)),                               cheStakerEarnings_FDT);  // Che got portion of interest
        assertEq(IERC20(USDC).balanceOf(address(stakeLocker)), totalStakerEarnings - cheStakerEarnings_FDT);  // Interest was transferred out of SL

        assertEq(bPool.balanceOf(address(che)),          25 * WAD);  // Che unstaked BPTs
        assertEq(bPool.balanceOf(address(stakeLocker)),  50 * WAD);  // PD + Staker stake
        assertEq(stakeLocker.totalSupply(),              50 * WAD);  // Total supply of stake tokens has decreased
        assertEq(stakeLocker.balanceOf(address(che)),           0);  // Che has no stake tokens after unstake
        assertEq(stakeLocker.stakeDate(address(che)),   stakeDate);  // StakeDate remains unchanged (doesn't matter since balanceOf == 0 on next stake)
    }
} 
