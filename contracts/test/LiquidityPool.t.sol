// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";

import "../AmortizationRepaymentCalc.sol";
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
    function try_fundLoan(address pool1, address loan, address dlFactory1, uint256 amt) external returns (bool ok) {
        string memory sig = "fundLoan(address,address,uint256)";
        (ok,) = address(pool1).call(abi.encodeWithSignature(sig, loan, dlFactory1, amt));
    }

    function createPool(
        address liqPoolFactory, 
        address liqAsset,
        address stakeAsset,
        uint256 stakingFee,
        uint256 delegateFee
    ) 
        external returns (address liquidityPool) 
    {
        liquidityPool = IPoolFactory(liqPoolFactory).createPool(
            liqAsset,
            stakeAsset,
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

    function claim(address pool, address loan, address dlFactory) external returns(uint[5] memory) {
        return IPool(pool).claim(loan, dlFactory);  
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
        address requestedAsset, 
        address collateralAsset, 
        uint256[6] memory specs,
        address[3] memory calcs
    ) 
        external returns (Loan loan) 
    {
        loan = Loan(
            loanFactory.createLoan(requestedAsset, collateralAsset, specs, calcs)
        );
    }
}

contract PoolTest is TestUtil {

    ERC20                           fundsToken;
    MapleToken                             mpl;
    MapleGlobals                       globals;
    FundingLockerFactory             flFactory;
    CollateralLockerFactory          clFactory;
    LoanFactory                   loanVFactory;
    Loan                                  loan;
    Loan                                 loan2;
    PoolFactory                 liqPoolFactory;
    StakeLockerFactory           stakeLFactory;
    LiquidityLockerFactory         liqLFactory; 
    DebtLockerFactory               dlFactory1; 
    DebtLockerFactory               dlFactory2; 
    Pool                                 pool1; 
    Pool                                 pool2; 
    DSValue                          ethOracle;
    DSValue                          daiOracle;
    AmortizationRepaymentCalc       amortiCalc;
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

    
    event DebugS(string, uint);

    function setUp() public {

        mpl            = new MapleToken("MapleToken", "MAPL", USDC);
        globals        = new MapleGlobals(address(this), address(mpl));
        flFactory      = new FundingLockerFactory();
        clFactory      = new CollateralLockerFactory();
        loanVFactory   = new LoanFactory(address(globals), address(flFactory), address(clFactory));
        stakeLFactory  = new StakeLockerFactory();
        liqLFactory    = new LiquidityLockerFactory();
        liqPoolFactory = new PoolFactory(address(globals), address(stakeLFactory), address(liqLFactory));
        dlFactory1     = new DebtLockerFactory();
        dlFactory2     = new DebtLockerFactory();
        ethOracle      = new DSValue();
        daiOracle      = new DSValue();
        amortiCalc     = new AmortizationRepaymentCalc();
        bulletCalc     = new BulletRepaymentCalc();
        lateFeeCalc    = new LateFeeCalc(0);   // Flat 0% fee
        premiumCalc    = new PremiumCalc(500); // Flat 5% premium
        sid            = new PoolDelegate();
        joe            = new PoolDelegate();
        bob            = new LP();
        che            = new LP();
        dan            = new LP();
        kim            = new LP();
        eli            = new Borrower();
        fay            = new Borrower();

        ethOracle.poke(500 ether);  // Set ETH price to $600
        daiOracle.poke(1 ether);    // Set DAI price to $1

        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * 10 ** 6);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), uint(-1));
        mpl.approve(address(bPool), uint(-1));

        bPool.bind(USDC, 50_000_000 * 10 ** 6, 5 ether);          // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl), 100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * 10 ** 6);
        assertEq(mpl.balanceOf(address(bPool)),   100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized

        globals.setPoolDelegateWhitelist(address(sid), true);
        globals.setPoolDelegateWhitelist(address(joe), true);
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(sid), bPool.balanceOf(address(this)) / 2);
        bPool.transfer(address(joe), bPool.balanceOf(address(this)));

        // Set Globals
        globals.setCalc(address(amortiCalc),  true);
        globals.setCalc(address(bulletCalc),  true);
        globals.setCalc(address(lateFeeCalc), true);
        globals.setCalc(address(premiumCalc), true);
        globals.setCollateralAsset(WETH, true);
        globals.setLoanAsset(DAI, true);
        globals.assignPriceFeed(WETH, address(ethOracle));
        globals.assignPriceFeed(DAI, address(daiOracle));
        globals.setMapleBPool(address(bPool));
        globals.setMapleBPoolAssetPair(USDC);
        globals.setStakeRequired(100 * 10 ** 6);

        // Create Liquidity Pool
        pool1 = Pool(sid.createPool(
            address(liqPoolFactory),
            DAI,
            address(bPool),
            500,
            100
        ));

        // Create Liquidity Pool
        pool2 = Pool(joe.createPool(
            address(liqPoolFactory),
            DAI,
            address(bPool),
            7500,
            50
        ));

        // loan Specifications
        uint256[6] memory specs_loan = [500, 180, 30, uint256(1000 ether), 2000, 7];
        address[3] memory calcs_loan = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        // loan2 Specifications
        uint256[6] memory specs_loan2 = [500, 180, 30, uint256(1000 ether), 2000, 7];
        address[3] memory calcs_loan2 = [address(amortiCalc), address(lateFeeCalc), address(premiumCalc)];

        loan  = eli.createLoan(loanVFactory, DAI, WETH, specs_loan, calcs_loan);
        loan2 = fay.createLoan(loanVFactory, DAI, WETH, specs_loan2, calcs_loan2);
    }

    function test_stake_and_finalize() public {

        /*****************************************/
        /*** Approve Stake Locker To Take BPTs ***/
        /*****************************************/
        address stakeLocker1 = pool1.stakeLocker();
        address stakeLocker2 = pool2.stakeLocker();
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

        sid.approve(address(bPool), stakeLocker, uint(-1));
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        // Mint 100 DAI into this LP account
        mint("DAI", address(bob), 100 ether);

        assertTrue(!bob.try_deposit(address(pool1), 100 ether)); // Not finalized

        pool1.finalize();

        assertTrue(!bob.try_deposit(address(pool1), 100 ether)); // Not approved

        bob.approve(DAI, address(pool1), uint(-1));

        assertEq(IERC20(DAI).balanceOf(address(bob)), 100 ether);
        assertEq(IERC20(DAI).balanceOf(liqLocker),            0);
        assertEq(pool1.balanceOf(address(bob)),             0);

        assertTrue(bob.try_deposit(address(pool1), 100 ether));

        assertEq(IERC20(DAI).balanceOf(address(bob)),         0);
        assertEq(IERC20(DAI).balanceOf(liqLocker),    100 ether);
        assertEq(pool1.balanceOf(address(bob)),     100 ether);
    }

    function test_fundLoan() public {
        address stakeLocker   = pool1.stakeLocker();
        address liqLocker     = pool1.liquidityLocker();
        address fundingLocker = loan.fundingLocker();

        sid.approve(address(bPool), stakeLocker, uint(-1));
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        // Mint 100 DAI into this LP account
        mint("DAI", address(bob), 100 ether);

        pool1.finalize();

        bob.approve(DAI, address(pool1), uint(-1));

        assertTrue(bob.try_deposit(address(pool1), 100 ether));

        assertTrue(!sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 100 ether)); // LoanFactory not in globals

        globals.setLoanFactory(address(loanVFactory));

        assertEq(IERC20(DAI).balanceOf(liqLocker),               100 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),          0);  // Balance of Funding Locker
        
        /*******************/
        /*** Fund a Loan ***/
        /*******************/
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 20 ether));  // Fund loan for 20 DAI

        DebtLocker debtLocker = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));

        assertEq(debtLocker.loan(), address(loan));
        assertEq(debtLocker.owner(), address(pool1));
        assertEq(debtLocker.loanAsset(), DAI);

        assertEq(IERC20(DAI).balanceOf(liqLocker),              80 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 20 ether);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),         20 ether);  // LoanToken balance of LT Locker
        assertEq(pool1.principalOut(),                            20 ether);  // Outstanding principal in liqiudity pool 1

        /****************************************/
        /*** Fund same loan with the same LTL ***/
        /****************************************/
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory1), 25 ether)); // Fund same loan for 25 DAI

        assertEq(dlFactory1.owner(address(debtLocker)), address(pool1));
        assertTrue(dlFactory1.isLocker(address(debtLocker)));

        assertEq(IERC20(DAI).balanceOf(liqLocker),              55 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 45 ether);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker)),         45 ether);  // LoanToken balance of LT Locker
        assertEq(pool1.principalOut(),                            45 ether);  // Outstanding principal in liqiudity pool 1

        /*******************************************/
        /*** Fund same loan with a different LTL ***/
        /*******************************************/
        DebtLockerFactory dlFactory2 = new DebtLockerFactory();
        assertTrue(sid.try_fundLoan(address(pool1), address(loan), address(dlFactory2), 10 ether)); // Fund loan for 15 DAI

        DebtLocker debtLocker2 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory2)));

        assertEq(debtLocker2.loan(), address(loan));
        assertEq(debtLocker2.owner(), address(pool1));
        assertEq(debtLocker2.loanAsset(), DAI);

        assertEq(dlFactory2.owner(address(debtLocker2)), address(pool1));
        assertTrue(dlFactory2.isLocker(address(debtLocker2)));

        assertEq(IERC20(DAI).balanceOf(liqLocker),              45 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 55 ether);  // Balance of Funding Locker
        assertEq(IERC20(loan).balanceOf(address(debtLocker2)),        10 ether);  // LoanToken balance of LT Locker 2
        assertEq(pool1.principalOut(),                            55 ether);  // Outstanding principal in liqiudity pool 1
    }

    // TODO: Add in pre-state and post-state checks for principalOut value.
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
            assertEq(balances[5] - balances[0], 0);  // LTL locker should have transferred ALL funds claimed to LP
            assertEq(balances[6] - balances[1], 0);  // LP         should have transferred ALL funds claimed to LL, SL, and PD

            assertEq(balances[7] - balances[2], claim[3] + claim[1] * pool.delegateFee() / 10_000);  // Pool delegate claim (feePaid + delegateFee portion of interest)
            assertEq(balances[8] - balances[3],            claim[1] * pool.stakingFee()  / 10_000);  // Staking Locker claim (feePaid + stakingFee portion of interest)

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
            sid.approve(address(bPool), pool1.stakeLocker(), uint(-1));
            sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

            pool1.finalize();
        }
        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        {
            mint("DAI", address(bob), 1_000_000_000 ether);
            mint("DAI", address(che), 1_000_000_000 ether);
            mint("DAI", address(dan), 1_000_000_000 ether);

            bob.approve(DAI, address(pool1), uint(-1));
            che.approve(DAI, address(pool1), uint(-1));
            dan.approve(DAI, address(pool1), uint(-1));

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 ether));  // 10%
            assertTrue(che.try_deposit(address(pool1), 300_000_000 ether));  // 30%
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 ether));  // 60%

            globals.setLoanFactory(address(loanVFactory)); // Don't remove, not done in setUp()
        }

        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        {
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 ether));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 100_000_000 ether));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 200_000_000 ether));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 200_000_000 ether));

            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory1),  50_000_000 ether));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory1),  50_000_000 ether));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 150_000_000 ether));
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 150_000_000 ether));
        }

        DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));  // debtLocker1 = DebtLocker 1, for loan using dlFactory1
        DebtLocker debtLocker2 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory2)));  // debtLocker2 = DebtLocker 2, for loan using dlFactory2
        DebtLocker debtLocker3 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory1)));  // debtLocker3 = DebtLocker 3, for loan2 using dlFactory1
        DebtLocker debtLocker4 = DebtLocker(pool1.debtLockers(address(loan2), address(dlFactory2)));  // debtLocker4 = DebtLocker 4, for loan2 using dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(100_000_000 ether); // wETH required for 100_000_000 DAI drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(100_000_000 ether); // wETH required for 100_000_000 DAI drawdown on loan2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(loan),  cReq1);
            fay.approve(WETH, address(loan2), cReq2);
            eli.drawdown(address(loan),  100_000_000 ether);
            fay.drawdown(address(loan2), 100_000_000 ether);
        }
        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        {
            (uint amt1_1,,,) =  loan.getNextPayment(); // DAI required for 1st payment on loan
            (uint amt1_2,,,) = loan2.getNextPayment(); // DAI required for 1st payment on loan2
            mint("DAI", address(eli), amt1_1);
            mint("DAI", address(fay), amt1_2);
            eli.approve(DAI, address(loan),  amt1_1);
            fay.approve(DAI, address(loan2), amt1_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
        {      
            checkClaim(debtLocker1, loan,  sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker2, loan,  sid, IERC20(DAI), pool1, address(dlFactory2));
            checkClaim(debtLocker3, loan2, sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker4, loan2, sid, IERC20(DAI), pool1, address(dlFactory2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        {
            (uint amt2_1,,,) =  loan.getNextPayment(); // DAI required for 2nd payment on loan
            (uint amt2_2,,,) = loan2.getNextPayment(); // DAI required for 2nd payment on loan2
            mint("DAI", address(eli), amt2_1);
            mint("DAI", address(fay), amt2_2);
            eli.approve(DAI, address(loan),  amt2_1);
            fay.approve(DAI, address(loan2), amt2_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));

            (uint amt3_1,,,) =  loan.getNextPayment(); // DAI required for 3rd payment on loan
            (uint amt3_2,,,) = loan2.getNextPayment(); // DAI required for 3rd payment on loan2
            mint("DAI", address(eli), amt3_1);
            mint("DAI", address(fay), amt3_2);
            eli.approve(DAI, address(loan),  amt3_1);
            fay.approve(DAI, address(loan2), amt3_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
        {      
            checkClaim(debtLocker1, loan,  sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker2, loan,  sid, IERC20(DAI), pool1, address(dlFactory2));
            checkClaim(debtLocker3, loan2, sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker4, loan2, sid, IERC20(DAI), pool1, address(dlFactory2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // DAI required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // DAI required for 2nd payment on loan2
            mint("DAI", address(eli), amtf_1);
            mint("DAI", address(fay), amtf_2);
            eli.approve(DAI, address(loan),  amtf_1);
            fay.approve(DAI, address(loan2), amtf_2);
            eli.makeFullPayment(address(loan));
            fay.makeFullPayment(address(loan2));
        }
        
        /****************/
        /*** LP Claim ***/
        /****************/
        {      
            checkClaim(debtLocker1, loan,  sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker2, loan,  sid, IERC20(DAI), pool1, address(dlFactory2));
            checkClaim(debtLocker3, loan2, sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker4, loan2, sid, IERC20(DAI), pool1, address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }
    }

    function test_claim_multipleLP() public {

        /******************************************/
        /*** Stake & Finalize 2 Liquidity Pools ***/
        /******************************************/
        address stakeLocker1 = pool1.stakeLocker();
        address stakeLocker2 = pool2.stakeLocker();
        {
            sid.approve(address(bPool), stakeLocker1, uint(-1));
            joe.approve(address(bPool), stakeLocker2, uint(-1));
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
            mint("DAI", address(bob), 1_000_000_000 ether);
            mint("DAI", address(che), 1_000_000_000 ether);
            mint("DAI", address(dan), 1_000_000_000 ether);

            bob.approve(DAI, address(pool1), uint(-1));
            che.approve(DAI, address(pool1), uint(-1));
            dan.approve(DAI, address(pool1), uint(-1));

            bob.approve(DAI, address(pool2), uint(-1));
            che.approve(DAI, address(pool2), uint(-1));
            dan.approve(DAI, address(pool2), uint(-1));

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 ether));  // 10% BOB in LP1
            assertTrue(che.try_deposit(address(pool1), 300_000_000 ether));  // 30% CHE in LP1
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 ether));  // 60% DAN in LP1

            assertTrue(bob.try_deposit(address(pool2), 500_000_000 ether));  // 50% BOB in LP2
            assertTrue(che.try_deposit(address(pool2), 400_000_000 ether));  // 40% BOB in LP2
            assertTrue(dan.try_deposit(address(pool2), 100_000_000 ether));  // 10% BOB in LP2

            globals.setLoanFactory(address(loanVFactory)); // Don't remove, not done in setUp()
        }
        
        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

        /***************************/
        /*** Fund loan / loan2 ***/
        /***************************/
        {
            // LP 1 Vault 1
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 25_000_000 ether));  // Fund loan using dlFactory1 for 25m DAI
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 25_000_000 ether));  // Fund loan using dlFactory1 for 25m DAI, again, 50m DAI total
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 25_000_000 ether));  // Fund loan using dlFactory2 for 25m DAI
            assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 25_000_000 ether));  // Fund loan using dlFactory2 for 25m DAI (no excess), 100m DAI total

            // LP 2 Vault 1
            assertTrue(joe.try_fundLoan(address(pool2), address(loan),  address(dlFactory1), 50_000_000 ether));  // Fund loan using dlFactory1 for 50m DAI (excess), 150m DAI total
            assertTrue(joe.try_fundLoan(address(pool2), address(loan),  address(dlFactory2), 50_000_000 ether));  // Fund loan using dlFactory2 for 50m DAI (excess), 200m DAI total

            // LP 1 Vault 2
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory1), 50_000_000 ether));  // Fund loan2 using dlFactory1 for 50m DAI
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory1), 50_000_000 ether));  // Fund loan2 using dlFactory1 for 50m DAI, again, 100m DAI total
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory2), 50_000_000 ether));  // Fund loan2 using dlFactory2 for 50m DAI
            assertTrue(sid.try_fundLoan(address(pool1), address(loan2),  address(dlFactory2), 50_000_000 ether));  // Fund loan2 using dlFactory2 for 50m DAI again, 200m DAI total

            // LP 2 Vault 2
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory1), 100_000_000 ether));  // Fund loan2 using dlFactory1 for 100m DAI
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory1), 100_000_000 ether));  // Fund loan2 using dlFactory1 for 100m DAI, again, 400m DAI total
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory2), 100_000_000 ether));  // Fund loan2 using dlFactory2 for 100m DAI (excess)
            assertTrue(joe.try_fundLoan(address(pool2), address(loan2),  address(dlFactory2), 100_000_000 ether));  // Fund loan2 using dlFactory2 for 100m DAI (excess), 600m DAI total
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
        assertEq(IERC20(DAI).balanceOf(liqLocker1),              700_000_000 ether);  // 1b DAI deposited - (100m DAI - 200m DAI)
        assertEq(IERC20(DAI).balanceOf(liqLocker2),              500_000_000 ether);  // 1b DAI deposited - (100m DAI - 400m DAI)
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),  200_000_000 ether);  // Balance of loan fl 
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker2)), 600_000_000 ether);  // Balance of loan2 fl (no excess, exactly 400 DAI from LP1 & 600 DAI from LP2)
        assertEq(loan.balanceOf(address(debtLocker1_pool1)),              50_000_000 ether);  // Balance of debtLocker1 for pool1 with dlFactory1
        assertEq(loan.balanceOf(address(debtLocker2_pool1)),              50_000_000 ether);  // Balance of debtLocker2 for pool1 with dlFactory2
        assertEq(loan2.balanceOf(address(debtLocker3_pool1)),            100_000_000 ether);  // Balance of debtLocker3 for pool1 with dlFactory1
        assertEq(loan2.balanceOf(address(debtLocker4_pool1)),            100_000_000 ether);  // Balance of debtLocker4 for pool1 with dlFactory2
        assertEq(loan.balanceOf(address(debtLocker1_pool2)),              50_000_000 ether);  // Balance of debtLocker1 for pool2 with dlFactory1
        assertEq(loan.balanceOf(address(debtLocker2_pool2)),              50_000_000 ether);  // Balance of debtLocker2 for pool2 with dlFactory2
        assertEq(loan2.balanceOf(address(debtLocker3_pool2)),            200_000_000 ether);  // Balance of debtLocker3 for pool2 with dlFactory1
        assertEq(loan2.balanceOf(address(debtLocker4_pool2)),            200_000_000 ether);  // Balance of debtLocker4 for pool2 with dlFactory2

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq1 =  loan.collateralRequiredForDrawdown(500_000_000 ether); // wETH required for 500m DAI drawdown on loan
            uint cReq2 = loan2.collateralRequiredForDrawdown(400_000_000 ether); // wETH required for 500m DAI drawdown on loan2
            mint("WETH", address(eli), cReq1);
            mint("WETH", address(fay), cReq2);
            eli.approve(WETH, address(loan),  cReq1);
            fay.approve(WETH, address(loan2), cReq2);
            eli.drawdown(address(loan),  100_000_000 ether); // 100m excess to be returned
            fay.drawdown(address(loan2), 300_000_000 ether); // 200m excess to be returned
        }

        
        /****************************/
        /*** Make 1 Payment (1/6) ***/
        /****************************/
        {
            (uint amt1_1,,,) =  loan.getNextPayment(); // DAI required for 1st payment on loan
            (uint amt1_2,,,) = loan2.getNextPayment(); // DAI required for 1st payment on loan2
            mint("DAI", address(eli), amt1_1);
            mint("DAI", address(fay), amt1_2);
            eli.approve(DAI, address(loan),  amt1_1);
            fay.approve(DAI, address(loan2), amt1_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        {
            checkClaim(debtLocker1_pool1, loan,  sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker2_pool1, loan,  sid, IERC20(DAI), pool1, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker4_pool1, loan2, sid, IERC20(DAI), pool1, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  joe, IERC20(DAI), pool2, address(dlFactory1));
            checkClaim(debtLocker2_pool2, loan,  joe, IERC20(DAI), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, joe, IERC20(DAI), pool2, address(dlFactory1));
            checkClaim(debtLocker4_pool2, loan2, joe, IERC20(DAI), pool2, address(dlFactory2));
        }

        /******************************/
        /*** Make 2 Payments (3/6)  ***/
        /******************************/
        {
            (uint amt2_1,,,) =  loan.getNextPayment(); // DAI required for 2nd payment on loan
            (uint amt2_2,,,) = loan2.getNextPayment(); // DAI required for 2nd payment on loan2
            mint("DAI", address(eli), amt2_1);
            mint("DAI", address(fay), amt2_2);
            eli.approve(DAI, address(loan),  amt2_1);
            fay.approve(DAI, address(loan2), amt2_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));

            (uint amt3_1,,,) =  loan.getNextPayment(); // DAI required for 3rd payment on loan
            (uint amt3_2,,,) = loan2.getNextPayment(); // DAI required for 3rd payment on loan2
            mint("DAI", address(eli), amt3_1);
            mint("DAI", address(fay), amt3_2);
            eli.approve(DAI, address(loan),  amt3_1);
            fay.approve(DAI, address(loan2), amt3_2);
            eli.makePayment(address(loan));
            fay.makePayment(address(loan2));
        }


        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        {
            checkClaim(debtLocker1_pool1, loan,  sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker2_pool1, loan,  sid, IERC20(DAI), pool1, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker4_pool1, loan2, sid, IERC20(DAI), pool1, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  joe, IERC20(DAI), pool2, address(dlFactory1));
            checkClaim(debtLocker2_pool2, loan,  joe, IERC20(DAI), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, joe, IERC20(DAI), pool2, address(dlFactory1));
            checkClaim(debtLocker4_pool2, loan2, joe, IERC20(DAI), pool2, address(dlFactory2));
        }
        
        /*********************************/
        /*** Make (Early) Full Payment ***/
        /*********************************/
        {
            (uint amtf_1,,) =  loan.getFullPayment(); // DAI required for 2nd payment on loan
            (uint amtf_2,,) = loan2.getFullPayment(); // DAI required for 2nd payment on loan2
            mint("DAI", address(eli), amtf_1);
            mint("DAI", address(fay), amtf_2);
            eli.approve(DAI, address(loan),  amtf_1);
            fay.approve(DAI, address(loan2), amtf_2);
            eli.makeFullPayment(address(loan));
            fay.makeFullPayment(address(loan2));
        }
        
        /*****************/
        /***  LP Claim ***/
        /*****************/
        {
            checkClaim(debtLocker1_pool1, loan,  sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker2_pool1, loan,  sid, IERC20(DAI), pool1, address(dlFactory2));
            checkClaim(debtLocker3_pool1, loan2, sid, IERC20(DAI), pool1, address(dlFactory1));
            checkClaim(debtLocker4_pool1, loan2, sid, IERC20(DAI), pool1, address(dlFactory2));

            checkClaim(debtLocker1_pool2, loan,  joe, IERC20(DAI), pool2, address(dlFactory1));
            checkClaim(debtLocker2_pool2, loan,  joe, IERC20(DAI), pool2, address(dlFactory2));
            checkClaim(debtLocker3_pool2, loan2, joe, IERC20(DAI), pool2, address(dlFactory1));
            checkClaim(debtLocker4_pool2, loan2, joe, IERC20(DAI), pool2, address(dlFactory2));

            // Ensure both loans are matured.
            assertEq(uint256(loan.loanState()),  2);
            assertEq(uint256(loan2.loanState()), 2);
        }
    }

    function test_withdraw() public {

        /*******************************/
        /*** Finalize liquidity pool ***/
        /*******************************/
        address stakeLocker = pool1.stakeLocker();
        address liqLocker   = pool1.liquidityLocker();

        sid.approve(address(bPool), stakeLocker, uint(-1));
        sid.stake(pool1.stakeLocker(), bPool.balanceOf(address(sid)) / 2);

        pool1.finalize();

        /**************************************************/
        /*** Mint and deposit funds into liquidity pool ***/
        /**************************************************/
        mint("DAI", address(bob), 100 ether);
        mint("DAI", address(che), 100 ether);
        mint("DAI", address(dan), 100 ether);

        bob.approve(DAI, address(pool1), uint(-1));
        che.approve(DAI, address(pool1), uint(-1));
        dan.approve(DAI, address(pool1), uint(-1));

        assertTrue(bob.try_deposit(address(pool1), 10 ether));  // 10%
        assertTrue(che.try_deposit(address(pool1), 30 ether));  // 30%
        assertTrue(dan.try_deposit(address(pool1), 60 ether));  // 60%

        globals.setLoanFactory(address(loanVFactory));

        /*******************************************/
        /*** Create new dlFactory1 and Loan ***/
        /*******************************************/
        DebtLockerFactory dlFactory2 = new DebtLockerFactory();

        // Create Loan Vault
        uint256[6] memory specs = [500, 90, 30, uint256(1000 ether), 2000, 7];
        address[3] memory calcs = [address(bulletCalc), address(lateFeeCalc), address(premiumCalc)];

        Loan loan2 = Loan(loanVFactory.createLoan(DAI, WETH, specs, calcs));

        address fundingLocker  = loan.fundingLocker();
        address fundingLocker2 = loan2.fundingLocker();

        /******************/
        /*** Fund Loans ***/
        /******************/
        assertEq(IERC20(DAI).balanceOf(liqLocker),              100 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),         0);  // Balance of Funding Locker

        assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1),  20 ether));  // Fund loan for 20 DAI
        assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1),  25 ether));  // Fund same loan for 25 DAI
        assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory2), 15 ether));  // Fund new loan same loan for 15 DAI
        assertTrue(sid.try_fundLoan(address(pool1), address(loan2), address(dlFactory2), 15 ether));  // Fund new loan new loan for 15 DAI

        address ltLocker  = pool1.debtLockers(address(loan),  address(dlFactory1));
        address ltLocker2 = pool1.debtLockers(address(loan),  address(dlFactory2));
        address ltLocker3 = pool1.debtLockers(address(loan2), address(dlFactory2));

        assertEq(IERC20(DAI).balanceOf(liqLocker),               25 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),  60 ether);  // Balance of Funding Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker2)), 15 ether);  // Balance of Funding Locker of loan 2
        assertEq(IERC20(loan).balanceOf(ltLocker),              45 ether);  // LoanToken balance of LT Locker
        assertEq(IERC20(loan).balanceOf(ltLocker2),             15 ether);  // LoanToken balance of LT Locker 2
        assertEq(IERC20(loan2).balanceOf(ltLocker3),            15 ether);  // LoanToken balance of LT Locker 3

        assertEq(IERC20(DAI).balanceOf(address(bob)), 90 ether);
        bob.withdraw(address(pool1), pool1.balanceOf(address(bob)));
        assertEq(IERC20(DAI).balanceOf(address(bob)), 100 ether); // Paid back initial share of 10% of pool

        // TODO: Post-claim, multiple providers
    }
    function test_interest() public {

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

        /***********************************/
        /*** interest penalty calculator ***/
        /***********************************/
        {
            uint256 start = block.timestamp;
            assertEq(lp1.calcInterestPenalty(1 ether,address(bob)),1 ether);
            hevm.warp(start + globals.interestDelay()/3);
            isEq(lp1.calcInterestPenalty(1 ether,address(bob)),uint(2 ether) / 3,6);
            hevm.warp(start + globals.interestDelay()/2);
            isEq(lp1.calcInterestPenalty(2 ether,address(bob)),1 ether,6);
            hevm.warp(start + globals.interestDelay() + 1);
            assertEq(lp1.calcInterestPenalty(1 ether,address(bob)),0);
            hevm.warp(start + globals.interestDelay()*2);
            assertEq(lp1.calcInterestPenalty(1 ether,address(bob)),0);
            hevm.warp(start + globals.interestDelay()*1000);
            assertEq(lp1.calcInterestPenalty(1 ether,address(bob)),0);

        }


        /******************************************/
        /*** interest only penalty on withdrawl ***/
        /******************************************/
        {
            globals.setPenaltyBips(0);
            uint start = block.timestamp;
            mint("DAI", address(kim), 2000 ether);
            kim.approve(DAI, address(lp1), uint(-1));
            assertTrue(kim.try_deposit(address(lp1), 1000 ether));
            kim.withdraw(address(lp1), lp1.balanceOf(address(kim)));
            isEq(IERC20(DAI).balanceOf(address(kim)),2000 ether, 11);
            assertTrue(kim.try_deposit(address(lp1), 1000 ether));
            hevm.warp(start + globals.interestDelay()+1);
            kim.withdraw(address(lp1), lp1.balanceOf(address(kim)));
            assertGt(IERC20(DAI).balanceOf(address(kim)),2000 ether);
        }
        /******************************************/
        /*** interest only penalty on withdrawl ***/
        /******************************************/
        {
            globals.setPenaltyBips(500);
            uint start = block.timestamp;
            
            assertTrue(kim.try_deposit(address(lp1), 1000 ether));
            kim.withdraw(address(lp1), lp1.balanceOf(address(kim)));
            assertTrue(IERC20(DAI).balanceOf(address(kim))<2000 ether);
            assertTrue(IERC20(DAI).balanceOf(address(kim))>1950 ether);
            assertTrue(kim.try_deposit(address(lp1), 1000 ether));
            
            hevm.warp(start + globals.interestDelay()+1);
            kim.withdraw(address(lp1), lp1.balanceOf(address(kim)));
            assertGt(IERC20(DAI).balanceOf(address(kim)),1950 ether);

        }

        {
            mint("DAI", address(kim), 2000 ether);
            uint256 start = block.timestamp;
            log_named_uint("blocktime",block.timestamp);
            assertTrue(kim.try_deposit(address(lp1), 1000 ether));
            assertTrue(bob.try_deposit(address(lp1), 1_000_000 ether));
            assertEq(lp1.calcInterestPenalty(1 ether,address(kim)),1 ether);
            hevm.warp(start + globals.interestDelay()/2);
            isEq(lp1.calcInterestPenalty(1 ether,address(kim)),uint(1 ether)/2,6);
            hevm.warp(start + globals.interestDelay() +1);
            assertEq(lp1.calcInterestPenalty(1 ether,address(kim)),0);
            assertTrue(kim.try_deposit(address(lp1), 1000 ether));
            isEq(lp1.calcInterestPenalty(2 ether,address(kim)),uint(1 ether),6);
            hevm.warp(start + globals.interestDelay()*2+1);
            assertEq(lp1.calcInterestPenalty(1 ether,address(kim)),0);


        }
    }    
}
