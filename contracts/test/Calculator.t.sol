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
import "../PremiumFlatCalc.sol";

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

contract Treasury { }

contract PoolTest is TestUtil {

    ERC20                           fundsToken;
    MapleToken                             mpl;
    MapleGlobals                       globals;
    FundingLockerFactory             flFactory;
    CollateralLockerFactory          clFactory;
    LoanFactory                    loanFactory;
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
    DSValue                         usdcOracle;
    AmortizationRepaymentCalc       amortiCalc;
    BulletRepaymentCalc             bulletCalc;
    LateFeeCalc                    lateFeeCalc;
    PremiumFlatCalc                premiumCalc;
    IBPool                               bPool;
    PoolDelegate                           sid;
    PoolDelegate                           joe;
    LP                                     bob;
    LP                                     che;
    LP                                     dan;
    Borrower                               eli;
    Borrower                               fay;
    Treasury                               trs;

    
    event DebugS(string, uint);

    function setUp() public {

        fundsToken     = new ERC20("FundsToken", "FT");
        mpl            = new MapleToken("MapleToken", "MAPL", IERC20(fundsToken));
        globals        = new MapleGlobals(address(this), address(mpl));
        flFactory      = new FundingLockerFactory();
        clFactory      = new CollateralLockerFactory();
        loanFactory    = new LoanFactory(address(globals), address(flFactory), address(clFactory));
        stakeLFactory  = new StakeLockerFactory();
        liqLFactory    = new LiquidityLockerFactory();
        liqPoolFactory = new PoolFactory(address(globals), address(stakeLFactory), address(liqLFactory));
        dlFactory1     = new DebtLockerFactory();
        dlFactory2     = new DebtLockerFactory();
        ethOracle      = new DSValue();
        usdcOracle     = new DSValue();
        amortiCalc     = new AmortizationRepaymentCalc();
        bulletCalc     = new BulletRepaymentCalc();
        lateFeeCalc    = new LateFeeCalc();
        premiumCalc    = new PremiumFlatCalc(500); // Flat 5% premium
        sid            = new PoolDelegate();
        joe            = new PoolDelegate();
        bob            = new LP();
        che            = new LP();
        dan            = new LP();
        eli            = new Borrower();
        fay            = new Borrower();
        trs            = new Treasury();

        globals.setMapleTreasury(address(trs));

        ethOracle.poke(500 ether);  // Set ETH price to $600
        usdcOracle.poke(1 ether);    // Set USDC price to $1

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
        globals.setLoanAsset(USDC, true);
        globals.assignPriceFeed(WETH, address(ethOracle));
        globals.assignPriceFeed(USDC, address(usdcOracle));
        globals.setMapleBPool(address(bPool));
        globals.setMapleBPoolAssetPair(USDC);
        globals.setStakeRequired(100 * 10 ** 6);

        // Create Liquidity Pool
        pool1 = Pool(sid.createPool(
            address(liqPoolFactory),
            USDC,
            address(bPool),
            500,
            100
        ));
        // Loan Specifications
        uint256[6] memory specs_loan = [500, 360, 1, uint256(1000 * 10 ** 6), 2000, 7];
        address[3] memory calcs_loan = [address(amortiCalc), address(lateFeeCalc), address(premiumCalc)];

        loan  = eli.createLoan(loanFactory, USDC, WETH, specs_loan, calcs_loan);
    }

    function test_amortization() public {

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
            mint("USDC", address(bob), 1_000_000_000 ether);
            mint("USDC", address(che), 1_000_000_000 ether);
            mint("USDC", address(dan), 1_000_000_000 ether);

            bob.approve(USDC, address(pool1), uint(-1));
            che.approve(USDC, address(pool1), uint(-1));
            dan.approve(USDC, address(pool1), uint(-1));

            assertTrue(bob.try_deposit(address(pool1), 100_000_000 ether));  // 10%
            assertTrue(che.try_deposit(address(pool1), 300_000_000 ether));  // 30%
            assertTrue(dan.try_deposit(address(pool1), 600_000_000 ether));  // 60%

            globals.setLoanFactory(address(loanFactory)); // Don't remove, not done in setUp()
        }

        address fundingLocker  = loan.fundingLocker();

        /************************************/
        /*** Fund loan / loan2 (Excess) ***/
        /************************************/
        assertTrue(sid.try_fundLoan(address(pool1), address(loan),  address(dlFactory1), 1_000 * 10 ** 6));
        DebtLocker debtLocker1 = DebtLocker(pool1.debtLockers(address(loan),  address(dlFactory1)));  // debtLocker1 = DebtLocker 1, for loan using dlFactory1

        /*****************/
        /*** Draw Down ***/
        /*****************/
        {
            uint cReq = loan.collateralRequiredForDrawdown(1_000 * 10 ** 6); // wETH required for 1_000 USDC drawdown on loan
            mint("WETH", address(eli), cReq);
            eli.approve(WETH, address(loan),  cReq);
            eli.drawdown(address(loan),  1_000 * 10 ** 6);
        }
        
        /*********************/
        /*** Make Payments ***/
        /*********************/
        while (loan.paymentsRemaining() != 0) {
            (uint amt1_1,,,) =  loan.getNextPayment(); // USDC required for 1st payment on loan
            mint("USDC", address(eli), amt1_1);
            eli.approve(USDC, address(loan),  amt1_1);
            eli.makePayment(address(loan));
        }
        
    }
    
}
