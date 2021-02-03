// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "./user/Governor.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IStakeLocker.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IERC20Details.sol";

import "../BulletRepaymentCalc.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../StakeLockerFactory.sol";
import "../PoolFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../DebtLockerFactory.sol";
import "../DebtLocker.sol";
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../LoanFactory.sol";
import "../Loan.sol";
import "../Pool.sol";

interface IBPoolFactory {
    function newBPool() external returns (address);
}

contract PoolDelegate {

    function createPool(
        address poolFactory, 
        address liquidityAsset,
        address stakeAsset,
        address slFactory, 
        address llFactory,
        uint256 stakingFee,
        uint256 delegateFee,
        uint256 liquidityCap
    ) 
        external returns (address liquidityPool) 
    {
        liquidityPool = IPoolFactory(poolFactory).createPool(
            liquidityAsset,
            stakeAsset,
            slFactory,
            llFactory,
            stakingFee,
            delegateFee,
            liquidityCap
        );
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function setWhitelistStakeLocker(address pool, address user, bool status) external {
        IPool(pool).setWhitelistStakeLocker(user, status);
    }

    function finalize(address pool) external {
        IPool(pool).finalize();
    }

    function unstake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).unstake(amt);
    }

    function fundLoan(address pool, address loan, address dlFactory, uint256 amt) external {
        IPool(pool).fundLoan(loan, dlFactory, amt);  
    }

    function claim(address pool, address loan, address dlFactory) external returns(uint256[7] memory) {
        return IPool(pool).claim(loan, dlFactory);  
    }
}

contract Staker {

    function try_stake(address stakeLocker, uint256 amt) external returns(bool ok) {
        string memory sig = "stake(uint256)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, amt));
    }

    function try_unstake(address stakeLocker, uint256 amt) external returns(bool ok) {
        string memory sig = "unstake(uint256)";
        (ok,) = address(stakeLocker).call(abi.encodeWithSignature(sig, amt));
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function try_transfer(address token, address dst, uint256 amt) external returns(bool ok) {
        string memory sig = "transfer(address,uint256)";
        (ok,) = address(token).call(abi.encodeWithSignature(sig, dst, amt));
    }

    function try_transferFrom(address token, address from, address to, uint256 amt) external returns(bool ok) {
        string memory sig = "transferFrom(address,address,uint256)";
        (ok,) = address(token).call(abi.encodeWithSignature(sig, from, to, amt));
    }

    function transfer(address token, address dst, uint256 amt) external {
        IERC20(token).transfer(dst, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function unstake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).unstake(amt);
    }

}

contract LP {

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function withdraw(address pool, uint256 amt) external {
        Pool(pool).withdraw(amt);
    }

    function deposit(address pool, uint256 amt) external {
        Pool(pool).deposit(amt);
    }
}

contract Borrower {

    function makePayment(address loan) external {
        Loan(loan).makePayment();
    }

    function makeFullPayment(address loan) external {
        Loan(loan).makeFullPayment();
    }

    function drawdown(address loan, uint256 _drawdownAmount) external {
        Loan(loan).drawdown(_drawdownAmount);
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function createLoan(
        LoanFactory loanFactory,
        address loanAsset, 
        address collateralAsset, 
        address flFactory,
        address clFactory,
        uint256[6] memory specs,
        address[3] memory calcs
    ) 
        external returns (Loan loanVault) 
    {
        loanVault = Loan(
            loanFactory.createLoan(loanAsset, collateralAsset, flFactory, clFactory, specs, calcs)
        );
    }
}

contract Treasury { }

contract StakeLockerTest is TestUtil {

    using SafeMath for uint256;

    Governor                               gov;
    MapleToken                             mpl;
    MapleGlobals                       globals;
    FundingLockerFactory             flFactory;
    CollateralLockerFactory          clFactory;
    LoanFactory                    loanFactory;
    Loan                                  loan;
    PoolFactory                    poolFactory;
    StakeLockerFactory               slFactory;
    LiquidityLockerFactory           llFactory; 
    DebtLockerFactory                dlFactory;  
    Pool                                  pool; 
    DSValue                          ethOracle;
    DSValue                         usdcOracle;
    BulletRepaymentCalc             bulletCalc;
    LateFeeCalc                    lateFeeCalc;
    PremiumCalc                    premiumCalc;
    IBPool                               bPool;
    PoolDelegate                           sid;
    LP                                     ali;
    Borrower                               bob;
    Staker                                 che;
    Staker                                 dan;
    Treasury                               trs;
    IStakeLocker                   stakeLocker;

    uint256 constant public MAX_UINT = uint(-1);

    function setUp() public {

        gov            = new Governor();
        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        flFactory      = new FundingLockerFactory();                                    // Setup the FL factory to facilitate Loan factory functionality.
        clFactory      = new CollateralLockerFactory();                                 // Setup the CL factory to facilitate Loan factory functionality.
        loanFactory    = new LoanFactory(address(globals));                             // Create Loan factory.
        slFactory      = new StakeLockerFactory();                                      // Setup the SL factory to facilitate Pool factory functionality.
        llFactory      = new LiquidityLockerFactory();                                  // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory    = new PoolFactory(address(globals));                             // Create pool factory.
        dlFactory      = new DebtLockerFactory();                                       // Setup DL factory to hold the cumulative funds for a loan corresponds to a pool.
        ethOracle      = new DSValue();                                                 // ETH Oracle.
        usdcOracle     = new DSValue();                                                 // USD Oracle.
        bulletCalc     = new BulletRepaymentCalc();                                     // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                                            // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);                                          // Flat 5% premium
        sid            = new PoolDelegate();                                            // Actor: Manager of the pool.
        ali            = new LP();                                                      // Actor: Liquidity providers
        bob            = new Borrower();                                                // Actor: Borrower aka Loan contract creator.
        che            = new Staker();                                                  // Actor: Staker of BPTs
        dan            = new Staker();                                                  // Actor: Staker of BPTs
        trs            = new Treasury();                                                // Treasury.

        gov.setValidLoanFactory(address(loanFactory), true);

        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);

        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(dlFactory), true);
        gov.setPriceOracle(WETH, 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        gov.setPriceOracle(WBTC, 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
        gov.setPriceOracle(USDC, 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);

        ethOracle.poke(500 ether);  // Set ETH price to $500
        usdcOracle.poke(1 ether);   // Set USDC price to $1

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * USD);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool), MAX_UINT);

        bPool.bind(USDC, 50_000_000 * USD, 5 ether);       // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl), 100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight

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
        gov.assignPriceFeed(WETH, address(ethOracle));
        gov.assignPriceFeed(USDC, address(usdcOracle));
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

        loan = bob.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        // Stake and finalize pool
        sid.approve(address(bPool), address(stakeLocker), 50 * WAD);
        sid.stake(address(stakeLocker), 50 * WAD);
        sid.finalize(address(pool));  // PD that staked can finalize

        assertEq(uint256(pool.poolState()), 1);  // Finalize
    }

    function test_stake() public {
        uint256 startDate = block.timestamp;

        assertTrue(!che.try_stake(address(stakeLocker),   25 * WAD));  // Hasn't approved BPTs
        che.approve(address(bPool), address(stakeLocker), 25 * WAD);

        assertTrue(!che.try_stake(address(stakeLocker),   25 * WAD));  // Isn't yet whitelisted
        che.approve(address(bPool), address(stakeLocker), 25 * WAD);

        sid.setWhitelistStakeLocker(address(pool), address(che), true);

        uint256 slBal_before = bPool.balanceOf(address(stakeLocker));

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
        uint256 slBal_before = bPool.balanceOf(address(stakeLocker));
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
