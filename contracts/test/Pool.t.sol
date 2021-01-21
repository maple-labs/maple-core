// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";

import "../BulletRepaymentCalc.sol";
import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
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
    function try_fundLoan(address pool, address loan, address dlFactory, uint256 amt) external returns (bool ok) {
        string memory sig = "fundLoan(address,address,uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, loan, dlFactory, amt));
    }

    function createPool(
        address poolFactory, 
        address liquidityAsset,
        address stakeAsset,
        address slFactory, 
        address llFactory,
        uint256 stakingFee,
        uint256 delegateFee
    ) 
        external returns (address liquidityPool) 
    {
        liquidityPool = IPoolFactory(poolFactory).createPool(
            liquidityAsset,
            stakeAsset,
            slFactory,
            llFactory,
            stakingFee,
            delegateFee
        );
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }

    function stake(address stakeLocker, uint256 amt) external {
        IStakeLocker(stakeLocker).stake(amt);
    }

    function fundLoan(address pool, address loan, address dlFactory, uint256 amt) external {
        return IPool(pool).fundLoan(loan, dlFactory, amt);  
    }

    function claim(address pool, address loan, address dlFactory) external returns(uint[5] memory) {
        return IPool(pool).claim(loan, dlFactory);  
    }

    function setPrincipalPenalty(address pool, uint256 penalty) external {
        return IPool(pool).setPrincipalPenalty(penalty);
    }

    function setInterestDelay(address pool, uint256 delay) external {
        return IPool(pool).setInterestDelay(delay);
    }
}

contract LP {
    function try_deposit(address pool1, uint256 amt)  external returns (bool ok) {
        string memory sig = "deposit(uint256)";
        (ok,) = address(pool1).call(abi.encodeWithSignature(sig, amt));
    }

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

contract PoolTest is TestUtil {

    using SafeMath for uint256;

    ERC20                           fundsToken;
    MapleToken                             mpl;
    MapleGlobals                       globals;
    FundingLockerFactory             flFactory;
    CollateralLockerFactory          clFactory;
    LoanFactory                    loanFactory;
    Loan                                  loan;
    Loan                                 loan2;
    Loan                                 loan3;
    PoolFactory                    poolFactory;
    StakeLockerFactory               slFactory;
    LiquidityLockerFactory           llFactory; 
    DebtLockerFactory               dlFactory1; 
    DebtLockerFactory               dlFactory2; 
    Pool                                 pool1; 
    Pool                                 pool2; 
    DSValue                          ethOracle;
    DSValue                         usdcOracle;
    BulletRepaymentCalc             bulletCalc;
    LateFeeCalc                    lateFeeCalc;
    PremiumCalc                    premiumCalc;
    IBPool                               bPool;
    PoolDelegate                           sid;
    PoolDelegate                           joe;
    LP                                     bob;
    LP                                     che;
    LP                                     dan;
    LP                                     kim;
    Borrower                               eli;
    Borrower                               fay;
    Borrower                               doe;
    Treasury                               trs;

    uint256 constant public MAX_UINT = uint(-1);

    function setUp() public {

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = new MapleGlobals(address(this), address(mpl), BPOOL_FACTORY);  //
        flFactory      = new FundingLockerFactory();                                    // Setup the FL factory to facilitate Loan facotry functionality.
        clFactory      = new CollateralLockerFactory();                                 // Setup the CL factory to facilitate Loan facotry functionality.
        loanFactory    = new LoanFactory(address(globals));                             // Create Loan factory.
        slFactory      = new StakeLockerFactory();                                      // Setup the SL factory to facilitate Pool factory functionality.
        llFactory      = new LiquidityLockerFactory();                                  // Setup the SL factory to facilitate Pool factory functionality.
        poolFactory    = new PoolFactory(address(globals));                             // Create pool factory.
        dlFactory1     = new DebtLockerFactory();                                       // Setup DL factory to hold the commulative funds for a loan corresponds to a pool.
        dlFactory2     = new DebtLockerFactory();                                       // Setup DL factory to hold the commulative funds for a loan corresponds to a pool.
        ethOracle      = new DSValue();                                                 // ETH Oracle.
        usdcOracle     = new DSValue();                                                 // USD Oracle.
        bulletCalc     = new BulletRepaymentCalc();                                     // Repayment model.
        lateFeeCalc    = new LateFeeCalc(0);                                            // Flat 0% fee
        premiumCalc    = new PremiumCalc(500);                                          // Flat 5% premium
        sid            = new PoolDelegate();                                            // Actor: Manager of the pool.
        joe            = new PoolDelegate();                                            // Actor: Manager of the pool.
        bob            = new LP();                                                      // Actor: Liquidity providers
        che            = new LP();                                                      // Actor: Liquidity providers
        dan            = new LP();                                                      // Actor: Liquidity providers
        kim            = new LP();                                                      // Actor: Liquidity providers
        eli            = new Borrower();                                                // Actor: Borrower aka Loan contract creator.
        fay            = new Borrower();                                                // Actor: Borrower aka Loan contract creator.
        doe            = new Borrower();                                                // Actor: Borrower aka Loan contract creator.
        trs            = new Treasury();                                                // Treasury.

        globals.setValidSubFactory(address(loanFactory), address(flFactory), true);
        globals.setValidSubFactory(address(loanFactory), address(clFactory), true);

        globals.setValidSubFactory(address(poolFactory), address(llFactory), true);
        globals.setValidSubFactory(address(poolFactory), address(slFactory), true);
        globals.setValidSubFactory(address(poolFactory), address(dlFactory1), true);
        globals.setValidSubFactory(address(poolFactory), address(dlFactory2), true);

        ethOracle.poke(500 ether);  // Set ETH price to $500
        usdcOracle.poke(1 ether);    // Set USDC price to $1

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

        globals.setPoolDelegateWhitelist(address(sid), true);
        globals.setPoolDelegateWhitelist(address(joe), true);
        globals.setMapleTreasury(address(trs));
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), bPool.balanceOf(address(this)) / 2);
        bPool.transfer(address(joe), bPool.balanceOf(address(this)));

        // Set Globals
        globals.setCalc(address(bulletCalc),  true);
        globals.setCalc(address(lateFeeCalc), true);
        globals.setCalc(address(premiumCalc), true);
        globals.setCollateralAsset(WETH, true);
        globals.setLoanAsset(USDC, true);
        globals.assignPriceFeed(WETH, address(ethOracle));
        globals.assignPriceFeed(USDC, address(usdcOracle));
        globals.setSwapOutRequired(100);

        // Create Liquidity Pool
        pool1 = Pool(sid.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100
        ));

        // Create Liquidity Pool
        pool2 = Pool(joe.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            7500,
            50
        ));

        // loan Specifications
        uint256[6] memory specs = [500, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        loan  = eli.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan2 = fay.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan3 = doe.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
    }

    function test_stake_and_finalize() public {

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        address stakeLocker1 = pool1.stakeLocker();
        address stakeLocker2 = pool2.stakeLocker();
        sid.approve(address(bPool), stakeLocker1, MAX_UINT);
        joe.approve(address(bPool), stakeLocker2, MAX_UINT);

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
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);
        joe.stake(pool2.stakeLocker(), bPool.balanceOf(address(joe)) / 2);

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
        pool1.finalize();
        pool2.finalize();

        // TODO: Post-state assertions to finalize().

    }

    function test_deposit() public {
        address stakeLocker = pool1.stakeLocker();
        address liqLocker   = pool1.liquidityLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        // Mint 100 USDC into this LP account
        mint("USDC", address(bob), 100 * USD);

        assertTrue(!bob.try_deposit(address(pool1), 100 * USD)); // Not finalized

        pool1.finalize();

        assertTrue(!bob.try_deposit(address(pool1), 100 * USD)); // Not approved

        bob.approve(USDC, address(pool1), MAX_UINT);

        assertEq(IERC20(USDC).balanceOf(address(bob)), 100 * USD);
        assertEq(IERC20(USDC).balanceOf(liqLocker),            0);
        assertEq(pool1.balanceOf(address(bob)),                0);

        assertTrue(bob.try_deposit(address(pool1),    100 * USD));

        assertEq(IERC20(USDC).balanceOf(address(bob)),         0);
        assertEq(IERC20(USDC).balanceOf(liqLocker),    100 * USD);
        assertEq(pool1.balanceOf(address(bob)),        100 * WAD);
    }

    function test_fundLoan() public {
        address stakeLocker   = pool1.stakeLocker();
        address liqLocker     = pool1.liquidityLocker();
        address fundingLocker = loan.fundingLocker();

        sid.approve(address(bPool), stakeLocker, MAX_UINT);
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        // Mint 100 USDC into this LP account
        mint("USDC", address(bob), 100 * USD);

        pool1.finalize();

        bob.approve(USDC, address(pool1), MAX_UINT);

        assertTrue(bob.try_deposit(address(pool1), 100 * USD));

        assertTrue(!sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 100 * USD)); // LoanFactory not in globals

        globals.setValidLoanFactory(address(loanFactory), true);

        assertEq(IERC20(USDC).balanceOf(liqLocker),               100 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)),          0);  // Balance of Funding Locker
        
        /*******************/
        /*** Fund a Loan ***/
        /*******************/
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 20 * USD), "Fail to fund a loan");  // Fund loan for 20 USDC

        DebtLocker debtLocker = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));

        assertEq(address(debtLocker.loan()), address(loan));
        assertEq(debtLocker.owner(), address(pool1));
        assertEq(address(debtLocker.loanAsset()), USDC);

        assertEq(IERC20(USDC).balanceOf(liqLocker),              80 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 20 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),    20 * WAD);  // LoanToken balance of LT Locker
        assertEq(pool1.principalOut(),                           20 * USD);  // Outstanding principal in liqiudity pool 1

        /****************************************/
        /*** Fund same loan with the same LTL ***/
        /****************************************/
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 25 * USD)); // Fund same loan for 25 USDC

        assertEq(dlFactory1.owner(address(debtLocker)), address(pool1));
        assertTrue(dlFactory1.isLocker(address(debtLocker)));

        assertEq(IERC20(USDC).balanceOf(liqLocker),              55 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 45 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),    45 * WAD);  // LoanToken balance of LT Locker
        assertEq(pool1.principalOut(),                           45 * USD);  // Outstanding principal in liqiudity pool 1

        /*******************************************/
        /*** Fund same loan with a different LTL ***/
        /*******************************************/
        DebtLockerFactory dlFactory2 = new DebtLockerFactory();
        globals.setValidSubFactory(address(poolFactory), address(dlFactory2), true);
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory2), 10 * USD)); // Fund loan for 15 USDC

        DebtLocker debtLocker2 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory2)));

        assertEq(address(debtLocker2.loan()), address(loan));
        assertEq(debtLocker2.owner(), address(pool1));
        assertEq(address(debtLocker2.loanAsset()), USDC);

        assertEq(dlFactory2.owner(address(debtLocker2)), address(pool1));
        assertTrue(dlFactory2.isLocker(address(debtLocker2)));

        assertEq(IERC20(USDC).balanceOf(liqLocker),              45 * USD);  // Balance of Liquidity Locker
        assertEq(IERC20(USDC).balanceOf(address(fundingLocker)), 55 * USD);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker2)),   10 * WAD);  // LoanToken balance of LT Locker 2
        assertEq(pool1.principalOut(),                           55 * USD);  // Outstanding principal in liqiudity pool 1
    }

    function checkClaim(DebtLocker debtLocker, Loan loan, PoolDelegate pd, IERC20 reqAsset, Pool pool, address dlFactory) internal {
        uint256[10] memory balances = [
            reqAsset.balanceOf(address(debtLocker)),
            reqAsset.balanceOf(address(pool)),
            reqAsset.balanceOf(address(pd)),
            reqAsset.balanceOf(pool.stakeLocker()),
            reqAsset.balanceOf(pool.liquidityLocker()),
            0,0,0,0,0
        ];

        uint256[4] memory loanData = [
            loan.interestPaid(),
            loan.principalPaid(),
            loan.feePaid(),
            loan.excessReturned()
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
        uint[5] memory claim = pd.claim(address(pool), address(loan),   address(dlFactory));

        // Updated LTL state variables
        debtLockerData[4] = debtLocker.interestPaid();
        debtLockerData[5] = debtLocker.principalPaid();
        debtLockerData[6] = debtLocker.feePaid();
        debtLockerData[7] = debtLocker.excessReturned();

        balances[5] = reqAsset.balanceOf(address(debtLocker));
        balances[6] = reqAsset.balanceOf(address(pool));
        balances[7] = reqAsset.balanceOf(address(pd));
        balances[8] = reqAsset.balanceOf(pool.stakeLocker());
        balances[9] = reqAsset.balanceOf(pool.liquidityLocker());

        uint256 sumTransfer;
        uint256 sumNetNew;

        for(uint i = 0; i < 4; i++) sumNetNew += (loanData[i] - debtLockerData[i]);

        {
            for(uint i = 0; i < 4; i++) {
                assertEq(debtLockerData[i + 4], loanData[i]);  // LTL updated to reflect loan state

                // Category portion of claim * LTL asset balance 
                // Eg. (interestClaimed / totalClaimed) * balance = Portion of total claim balance that is interest
                uint256 loanShare = (loanData[i] - debtLockerData[i]) * 1 ether / sumNetNew * claim[0] / 1 ether;
                assertEq(loanShare, claim[i + 1]);

                sumTransfer += balances[i + 6] - balances[i + 1]; // Sum up all transfers that occured from claim
            }
            assertEq(claim[0], sumTransfer); // Assert balance from withdrawFunds equals sum of transfers
        }

        {
            assertEq(balances[5] - balances[0], 0);      // LTL locker should have transferred ALL funds claimed to LP
            assertTrue(balances[6] - balances[1] < 10);  // LP         should have transferred ALL funds claimed to LL, SL, and PD (with rounding error)

            assertEq(balances[7] - balances[2], claim[3] + claim[1] * pool.delegateFee() / 10_000);  // Pool delegate claim (feePaid + delegateFee portion of interest)
            assertEq(balances[8] - balances[3],            claim[1] * pool.stakingFee()  / 10_000);  // Staking Locker claim (feePaid + stakingFee portion of interest)

            withinPrecision(pool.interestSum() - beforeInterestSum, claim[1] - claim[1] * (pool.delegateFee() + pool.stakingFee()) / 10_000, 11);  // interestSum incremented by remainder of interest

            // Liquidity Locker balance change should EXACTLY equal state variable change
            assertEq(balances[9] - balances[4], (beforePrincipalOut - pool.principalOut()) + (pool.interestSum() - beforeInterestSum));

            assertTrue(beforePrincipalOut - pool.principalOut() == claim[2] + claim[4]); // principalOut incremented by claimed principal + excess
        }
    }

    function isConstantPoolValue(Pool pool, IERC20 loanAsset, uint256 constPoolVal) internal returns(bool) {
        return pool.principalOut() + loanAsset.balanceOf(pool.liquidityLocker()) == constPoolVal;
    }

    function assertConstFundLoan(Pool pool, address loan, address dlFactory, uint256 amt, IERC20 loanAsset, uint256 constPoolVal) internal returns(bool) {
        assertTrue(sid.try_fundLoan(address(pool), loan,  dlFactory, amt));
        assertTrue(isConstantPoolValue(pool1, loanAsset, constPoolVal));
    }

    function assertConstClaim(Pool pool, address loan, address dlFactory, IERC20 loanAsset, uint256 constPoolVal) internal returns(bool) {
        sid.claim(address(pool), loan, dlFactory);
        assertTrue(isConstantPoolValue(pool, loanAsset, constPoolVal));
    }

    function test_claim_principal_accounting() public {
        /*********************************************/
        /*** Create a loan with 0% APR, 0% premium ***/
        /*********************************************/
        premiumCalc = new PremiumCalc(0); // Flat 0% premium
        globals.setCalc(address(premiumCalc), true);

        uint256[6] memory specs = [0, 180, 30, uint256(1000 * USD), 2000, 7];
        address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        loan  = eli.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan2 = fay.createLoan(loanFactory, USDC, WETH, address(flFactory), address(clFactory), specs, calcs);

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        {
            sid.approve(address(bPool), pool1.stakeLocker(), uint(-1));
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

            pool1.finalize();
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

            globals.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

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
        
        /****************/
        /*** LP Claim ***/
        /****************/
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

            pool1.finalize();
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

            globals.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

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
            (uint amt1_1,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            (uint amt1_2,,,) = loan2.getNextPayment(); // USDC required for 1st payment on loan2
            mint("USDC", address(eli), amt1_1);
            mint("USDC", address(fay), amt1_2);
            eli.approve(USDC, address(loan),  amt1_1);
            fay.approve(USDC, address(loan2), amt1_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
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
            (uint amt2_1,,,) =  loan.getNextPayment(); // USDC required for 2nd payment on loan
            (uint amt2_2,,,) = loan2.getNextPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amt2_1);
            mint("USDC", address(fay), amt2_2);
            eli.approve(USDC, address(loan),  amt2_1);
            fay.approve(USDC, address(loan2), amt2_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));

            (uint amt3_1,,,) =  loan.getNextPayment(); // USDC required for 3rd payment on loan
            (uint amt3_2,,,) = loan2.getNextPayment(); // USDC required for 3rd payment on loan2
            mint("USDC", address(eli), amt3_1);
            mint("USDC", address(fay), amt3_2);
            eli.approve(USDC, address(loan),  amt3_1);
            fay.approve(USDC, address(loan2), amt3_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
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
        
        /****************/
        /*** LP Claim ***/
        /****************/
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
            pool1.finalize();
            pool2.finalize();
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

            globals.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
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
            (uint amt1_1,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            (uint amt1_2,,,) = loan2.getNextPayment(); // USDC required for 1st payment on loan2
            mint("USDC", address(eli), amt1_1);
            mint("USDC", address(fay), amt1_2);
            eli.approve(USDC, address(loan),  amt1_1);
            fay.approve(USDC, address(loan2), amt1_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
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
            (uint amt2_1,,,) =  loan.getNextPayment(); // USDC required for 2nd payment on loan
            (uint amt2_2,,,) = loan2.getNextPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amt2_1);
            mint("USDC", address(fay), amt2_2);
            eli.approve(USDC, address(loan),  amt2_1);
            fay.approve(USDC, address(loan2), amt2_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));

            (uint amt3_1,,,) =  loan.getNextPayment(); // USDC required for 3rd payment on loan
            (uint amt3_2,,,) = loan2.getNextPayment(); // USDC required for 3rd payment on loan2
            mint("USDC", address(eli), amt3_1);
            mint("USDC", address(fay), amt3_2);
            eli.approve(USDC, address(loan),  amt3_1);
            fay.approve(USDC, address(loan2), amt3_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }

        /*****************/
        /***  LP Claim ***/
        /*****************/
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
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
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

            pool1.finalize();

            globals.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
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
            (uint amt,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            mint("USDC", address(eli), amt);
            eli.approve(USDC, address(loan),  amt);
            eli.makePayment(address(loan));
        }

        /**********************************************/
        /*** Transfer USDC into Pool and debtLocker ***/
        /**********************************************/
        {
            DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));

            uint256 poolBal_before       = IERC20(USDC).balanceOf(address(pool1));
            uint256 debtLockerBal_before = IERC20(USDC).balanceOf(address(debtLocker1));

            IERC20(USDC).transferFrom(address(bob), address(pool1),       1000 * USD);
            IERC20(USDC).transferFrom(address(bob), address(debtLocker1), 2000 * USD);

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
        /*********************************************************/
        {
            DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));

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

            pool1.finalize();
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

            globals.setValidLoanFactory(address(loanFactory), true); // Don't remove, not done in setUp()
        }

        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

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
            (uint amt1_1,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            (uint amt1_2,,,) = loan2.getNextPayment(); // USDC required for 1st payment on loan2
            mint("USDC", address(eli), amt1_1);
            mint("USDC", address(fay), amt1_2);
            eli.approve(USDC, address(loan),  amt1_1);
            fay.approve(USDC, address(loan2), amt1_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
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
            (uint amt2_1,,,) =  loan.getNextPayment(); // USDC required for 2nd payment on loan
            (uint amt2_2,,,) = loan2.getNextPayment(); // USDC required for 2nd payment on loan2
            mint("USDC", address(eli), amt2_1);
            mint("USDC", address(fay), amt2_2);
            eli.approve(USDC, address(loan),  amt2_1);
            fay.approve(USDC, address(loan2), amt2_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));

            (uint amt3_1,,,) =  loan.getNextPayment(); // USDC required for 3rd payment on loan
            (uint amt3_2,,,) = loan2.getNextPayment(); // USDC required for 3rd payment on loan2
            mint("USDC", address(eli), amt3_1);
            mint("USDC", address(fay), amt3_2);
            eli.approve(USDC, address(loan),  amt3_1);
            fay.approve(USDC, address(loan2), amt3_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
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
        
        /****************/
        /*** LP Claim ***/
        /****************/
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
        uint256 delay = pool1.interestDelay();

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

    function test_withdraw_no_principal_penalty() public {
        setUpWithdraw();

        uint start = block.timestamp;

        sid.setPrincipalPenalty(address(pool1), 0);
        mint("USDC", address(kim), 2000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);
        assertTrue(kim.try_deposit(address(pool1), 1000 * USD));

        uint256 withdrawAmount = 1000 * USD;
        kim.withdraw(address(pool1), withdrawAmount);

        withinPrecision(IERC20(USDC).balanceOf(address(kim)), 2000 * USD, 6); // 100 % precesion.
        
        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));

        assertTrue(kim.try_deposit(address(pool1), 1000 * USD), "Fail to deposit liquidity");                                      // Add another 1000 USDC.
        assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1000 * USD), "Fail to fund the loan");   // Fund the loan.
        hevm.warp(start + pool1.interestDelay());                                                                                  // Fast-forward to claim all proportionate interest.
        _drawDownLoan(1000 * USD, loan3, doe);                                                                                     // Draw down the loan.
        _makeLoanPayment(loan3, doe);                                                                                              // Make loan payment.
        sid.claim(address(pool1), address(loan3), address(dlFactory1));                                                            // Fund claimed by the pool.

        uint256 interest = pool1.withdrawableFundsOf(address(kim));

        kim.withdraw(address(pool1), withdrawAmount);
        uint256 bal1 = IERC20(USDC).balanceOf(address(kim));

        withinPrecision(bal1 - bal0, interest, 6);
    }

    function test_withdraw_principal_penalty() public {
        setUpWithdraw();

        uint start = block.timestamp;
        
        sid.setPrincipalPenalty(address(pool1), 5000);
        mint("USDC", address(kim), 2000 * USD);
        kim.approve(USDC, address(pool1), MAX_UINT);

        uint256 bal0 = IERC20(USDC).balanceOf(address(kim));
        uint256 depositAmount = 1000 * USD;
        assertTrue(kim.try_deposit(address(pool1), depositAmount));      // Deposit and withdraw in same tx
        kim.withdraw(address(pool1), depositAmount);
        uint256 bal1 = IERC20(USDC).balanceOf(address(kim));            // Balance after principal penalty

        withinPrecision(bal0 - bal1, 50 * USD, 6); // 5% principal penalty with 100 % precesion.
        
        // Do another deposit with same amount
        bal0 = IERC20(USDC).balanceOf(address(kim));
        assertTrue(kim.try_deposit(address(pool1), depositAmount));                                                                // Add another 1000 USDC
        assertTrue(sid.try_fundLoan(address(pool1), address(loan3),  address(dlFactory1), 1000 * USD), "Fail to fund the loan");   // Fund the loan.
        _drawDownLoan(1000 * USD, loan3, doe);                                                                                     // Draw down the loan.
        hevm.warp(start + pool1.interestDelay() - 10 days);                                                                        // Fast-forward to claim all proportionate interest.
        _makeLoanPayment(loan3, doe);                                                                                              // Make loan payment.
        sid.claim(address(pool1), address(loan3), address(dlFactory1));                                                            // Fund claimed by the pool.

        uint256 withdrawAmount = depositAmount;
        uint256 interest       = pool1.withdrawableFundsOf(address(kim));
        uint256 priPenalty     = pool1.principalPenalty().mul(withdrawAmount).div(100000);           // Calculate flat principal penalty.
        uint256 totPenalty     = pool1.calcWithdrawPenalty(interest.add(priPenalty), address(kim));  // Get total penalty, however it may be calculated.
        
        kim.withdraw(address(pool1), withdrawAmount);
        bal1 = IERC20(USDC).balanceOf(address(kim));
        uint256 balanceDiff = bal1 > bal0 ? bal1 - bal0 : bal0 - bal1;
        uint256 extraAmount = totPenalty > interest ? totPenalty - interest : interest - totPenalty;
        withinPrecision(balanceDiff, extraAmount, 6); // All of principal returned, plus interest
    }

    function _makeLoanPayment(Loan loan, Borrower by) internal {
        (uint amt,,,) =  loan.getNextPayment();
        mint("USDC", address(by), amt);
        by.approve(USDC, address(loan),  amt);
        by.makePayment(address(loan));
    }

    function _drawDownLoan(uint256 drawDownAmount, Loan loan, Borrower by) internal  {
        uint cReq =  loan.collateralRequiredForDrawdown(drawDownAmount);
        mint("WETH", address(by), cReq);
        by.approve(WETH, address(loan),  cReq);
        by.drawdown(address(loan),  drawDownAmount);
    }
}
