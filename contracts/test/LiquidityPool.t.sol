pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/ILiquidityPool.sol";
import "../interfaces/ILiquidityPoolFactory.sol";

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
import "../FundingLockerFactory.sol";
import "../CollateralLockerFactory.sol";
import "../LoanVaultFactory.sol";
import "../LoanVault.sol";
import "../LiquidityPool.sol";

interface IBPoolFactory {
    function newBPool() external returns (address);
}

contract PoolDelegate {
    function try_fundLoan(address liqPool, address vault, address ltlFactory, uint256 amt) external returns (bool ok) {
        string memory sig = "fundLoan(address,address,uint256)";
        (ok,) = address(liqPool).call(abi.encodeWithSignature(sig, vault, ltlFactory, amt));
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
}

contract LP {
    function try_deposit(address liqPool, uint256 amt)  external returns (bool ok) {
        string memory sig = "deposit(uint256)";
        (ok,) = address(liqPool).call(abi.encodeWithSignature(sig, amt));
    }

    function approve(address token, address who, uint256 amt) external {
        IERC20(token).approve(who, amt);
    }
}

contract LiquidityPoolTest is TestUtil {

    ERC20                     fundsToken;
    MapleToken                mapleToken;
    MapleGlobals              globals;
    FundingLockerFactory      flFactory;
    CollateralLockerFactory   clFactory;
    LoanVaultFactory          loanVFactory;
    LoanVault                 vault;
    LiquidityPoolFactory      liqPoolFactory;
    StakeLockerFactory        stakeLFactory;
    LiquidityLockerFactory    liqLFactory; 
    LoanTokenLockerFactory    ltlFactory; 
    LiquidityPool             liqPool; 
    DSValue                   ethOracle;
    DSValue                   daiOracle;
    BulletRepaymentCalculator bulletCalc;
    LateFeeNullCalculator     lateFeeCalc;
    PremiumFlatCalculator     premiumCalc;
    PoolDelegate              ali;
    LP                        bob;
    IBPool                    bPool;

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
        ltlFactory     = new LoanTokenLockerFactory();
        ethOracle      = new DSValue();
        daiOracle      = new DSValue();
        bulletCalc     = new BulletRepaymentCalculator();
        lateFeeCalc    = new LateFeeNullCalculator();
        premiumCalc    = new PremiumFlatCalculator(500); // Flat 5% premium
        ali            = new PoolDelegate();
        bob            = new LP();

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

        globals.setPoolDelegateWhitelist(address(ali), true);
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        bPool.transfer(address(ali), bPool.balanceOf(address(this)));

        // Set Globals
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
        liqPool = LiquidityPool(ali.createLiquidityPool(
            address(liqPoolFactory),
            DAI,
            address(bPool),
            500,
            100,
            "Maple Liquidity Pool 0",
            "MPL_LP_0"
        ));

        // Create Loan Vault
        uint256[6] memory specs = [500, 90, 30, uint256(1000 ether), 2000, 7];
        bytes32[3] memory calcs = [bytes32("BULLET"), bytes32("NULL"), bytes32("FLAT")];

        vault = LoanVault(loanVFactory.createLoanVault(DAI, WETH, specs, calcs));
    }

    function test_stake_and_finalize() public {
        address stakeLocker = liqPool.stakeLockerAddress();

        ali.approve(address(bPool), stakeLocker, uint(-1));
        assertEq(bPool.balanceOf(address(ali)),               100 * WAD);
        assertEq(bPool.balanceOf(stakeLocker),                0);
        assertEq(IERC20(stakeLocker).balanceOf(address(ali)), 0);

        ali.stake(liqPool.stakeLockerAddress(), bPool.balanceOf(address(ali)) / 2);

        assertEq(bPool.balanceOf(address(ali)),               50 * WAD);
        assertEq(bPool.balanceOf(stakeLocker),                50 * WAD);
        assertEq(IERC20(stakeLocker).balanceOf(address(ali)), 50 * WAD);

        liqPool.finalize();
    }

    function test_deposit() public {
        address stakeLocker = liqPool.stakeLockerAddress();
        address liqLocker   = liqPool.liquidityLockerAddress();

        ali.approve(address(bPool), stakeLocker, uint(-1));
        ali.stake(liqPool.stakeLockerAddress(), bPool.balanceOf(address(ali)) / 2);

        // Mint 100 DAI into this LP account
        mint("DAI", address(bob), 100 ether);

        assertTrue(!bob.try_deposit(address(liqPool), 100 ether)); // Not finalized

        liqPool.finalize();

        assertTrue(!bob.try_deposit(address(liqPool), 100 ether)); // Not approved

        bob.approve(DAI, address(liqPool), uint(-1));

        assertEq(IERC20(DAI).balanceOf(address(bob)), 100 ether);
        assertEq(IERC20(DAI).balanceOf(liqLocker),            0);
        assertEq(liqPool.balanceOf(address(bob)),             0);

        assertTrue(bob.try_deposit(address(liqPool), 100 ether));

        assertEq(IERC20(DAI).balanceOf(address(bob)),         0);
        assertEq(IERC20(DAI).balanceOf(liqLocker),    100 ether);
        assertEq(liqPool.balanceOf(address(bob)),     100 ether);
    }

    function test_fundLoan() public {
        address stakeLocker   = liqPool.stakeLockerAddress();
        address liqLocker     = liqPool.liquidityLockerAddress();
        address fundingLocker = vault.fundingLocker();

        ali.approve(address(bPool), stakeLocker, uint(-1));
        ali.stake(liqPool.stakeLockerAddress(), bPool.balanceOf(address(ali)) / 2);

        // Mint 100 DAI into this LP account
        mint("DAI", address(bob), 100 ether);

        liqPool.finalize();

        bob.approve(DAI, address(liqPool), uint(-1));

        assertTrue(bob.try_deposit(address(liqPool), 100 ether));

        assertTrue(!ali.try_fundLoan(address(liqPool), address(vault), address(ltlFactory), 100 ether)); // LoanVaultFactory not in globals

        globals.setLoanVaultFactory(address(loanVFactory));

        assertEq(IERC20(DAI).balanceOf(liqLocker),               100 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)),          0);  // Balance of Funding Locker
        
        /*******************/
        /*** Fund a Loan ***/
        /*******************/
        assertTrue(ali.try_fundLoan(address(liqPool), address(vault), address(ltlFactory), 20 ether));  // Fund loan for 20 DAI

        (
            address loanVaultFunded,
            address loanTokenLocker,
            uint256 amountFunded,
            uint256 principalPaid,
            uint256 interestPaid,
            uint256 feePaid,
            uint256 excessReturned
        ) = liqPool.loans(address(vault), address(ltlFactory));

        assertEq(ltlFactory.lockers(0), loanTokenLocker);  // LTL instantiated

        assertEq(loanVaultFunded,  address(vault));
        assertEq(amountFunded,           20 ether); 
        assertEq(principalPaid,                 0);
        assertEq(interestPaid,                  0);
        assertEq(feePaid,                       0);
        assertEq(excessReturned,                0);

        assertEq(IERC20(DAI).balanceOf(liqLocker),              80 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 20 ether);  // Balance of Funding Locker
        assertEq(IERC20(vault).balanceOf(loanTokenLocker),      20 ether);  // LoanToken balance of LT Locker

        /****************************************/
        /*** Fund same loan with the same LTL ***/
        /****************************************/
        assertTrue(ali.try_fundLoan(address(liqPool), address(vault), address(ltlFactory), 25 ether)); // Fund loan for 25 DAI
        (
            loanVaultFunded,
            loanTokenLocker,
            amountFunded,
            principalPaid,
            interestPaid,
            feePaid,
            excessReturned
        ) = liqPool.loans(address(vault), address(ltlFactory));

        assertEq(ltlFactory.lockers(0), loanTokenLocker);  // Same LTL

        assertEq(loanVaultFunded,  address(vault));
        assertEq(amountFunded,           45 ether); 
        assertEq(principalPaid,                 0);
        assertEq(interestPaid,                  0);
        assertEq(feePaid,                       0);
        assertEq(excessReturned,                0);

        assertEq(IERC20(DAI).balanceOf(liqLocker),              55 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 45 ether);  // Balance of Funding Locker
        assertEq(IERC20(vault).balanceOf(loanTokenLocker),      45 ether);  // LoanToken balance of LT Locker

        /*******************************************/
        /*** Fund same loan with a different LTL ***/
        /*******************************************/
        LoanTokenLockerFactory ltlFactory2 = new LoanTokenLockerFactory();
        assertTrue(ali.try_fundLoan(address(liqPool), address(vault), address(ltlFactory2), 15 ether)); // Fund loan for 25 DAI

        (
            loanVaultFunded,
            loanTokenLocker,
            amountFunded,
            principalPaid,
            interestPaid,
            feePaid,
            excessReturned
        ) = liqPool.loans(address(vault), address(ltlFactory2)); // Next struct in mapping, corrresponding to new LTL

        assertEq(ltlFactory2.lockers(0), loanTokenLocker);  // Same LTL

        assertEq(loanVaultFunded,  address(vault));
        assertEq(amountFunded,           15 ether); 
        assertEq(principalPaid,                 0);
        assertEq(interestPaid,                  0);
        assertEq(feePaid,                       0);
        assertEq(excessReturned,                0);

        assertEq(IERC20(DAI).balanceOf(liqLocker),              40 ether);  // Balance of Liquidity Locker
        assertEq(IERC20(DAI).balanceOf(address(fundingLocker)), 60 ether);  // Balance of Funding Locker
        assertEq(IERC20(vault).balanceOf(loanTokenLocker),      15 ether);  // LoanToken balance of LT Locker
    }
}
