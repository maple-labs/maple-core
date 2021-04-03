// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./user/Borrower.sol";
import "./user/LP.sol";
import "./user/Staker.sol";
import "./user/Commoner.sol";
import "./user/PoolDelegate.sol";
import "./user/Governor.sol";
import "./user/SecurityAdmin.sol";
import "./user/EmergencyAdmin.sol";

import "../MapleGlobals.sol";
import "../MapleTreasury.sol";
import "module/maple-token/contracts/MapleToken.sol";

import "../PoolFactory.sol";
import "../StakeLockerFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../DebtLockerFactory.sol";
import "../LoanFactory.sol";
import "../CollateralLockerFactory.sol";
import "../FundingLockerFactory.sol";

import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";
import "../RepaymentCalc.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/IBFactory.sol";

import "lib/ds-test/contracts/test.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

interface User {
    function approve(address, uint256) external;
}

contract TestUtil is DSTest {

    Hevm hevm;

    /***********************/
    /*** Protocol Actors ***/
    /***********************/
    Borrower      bob;
    Borrower      ben;
    Borrower      bud;

    LP            leo;
    LP            liz;
    LP            lex;
    LP            lee;

    Staker        sam;
    Staker        sid;
    Staker        sue;

    Commoner      cam;

    PoolDelegate  pat;
    PoolDelegate  pam;

    /**************************/
    /*** Multisig Addresses ***/
    /**************************/
    Governor                   gov;
    Governor               fakeGov;
    SecurityAdmin    securityAdmin;
    EmergencyAdmin  emergencyAdmin;

    /*******************/
    /*** Calculators ***/
    /*******************/
    LateFeeCalc      lateFeeCalc;
    PremiumCalc      premiumCalc;
    RepaymentCalc  repaymentCalc;

    /*****************/
    /*** Factories ***/
    /*****************/
    CollateralLockerFactory    clFactory;
    DebtLockerFactory         dlFactory1;
    DebtLockerFactory         dlFactory2;
    FundingLockerFactory       flFactory;
    LiquidityLockerFactory     llFactory;
    LoanFactory              loanFactory;
    PoolFactory              poolFactory;
    StakeLockerFactory         slFactory;

    /***********************/
    /*** Maple Contracts ***/
    /***********************/
    MapleGlobals   globals;
    MapleToken         mpl;
    MapleTreasury treasury;
    IBPool           bPool;

    /***************/
    /*** Oracles ***/
    /***************/
    ChainlinkOracle  wethOracle;
    ChainlinkOracle  wbtcOracle;
    UsdOracle         usdOracle;

    /*************/
    /*** Loans ***/
    /*************/
    Loan   loan;
    Loan  loan2;
    Loan  loan3;
    Loan  loan4;

    /*************/
    /*** Pools ***/
    /*************/
    Pool   pool;
    Pool  pool2;
    Pool  pool3;

    /**********************************/
    /*** Mainnet Contract Addresses ***/
    /**********************************/
    address constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC  = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH  = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC  = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    IERC20 constant dai  = IERC20(DAI);
    IERC20 constant usdc = IERC20(USDC);
    IERC20 constant weth = IERC20(WETH);
    IERC20 constant wbtc = IERC20(WBTC);

    address constant BPOOL_FACTORY        = 0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd; // Balancer pool factory
    address constant UNISWAP_V2_ROUTER_02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router

    /*****************/
    /*** Constants ***/
    /*****************/
    uint256 constant USD = 10 ** 6;  // USDC precision decimals
    uint256 constant BTC = 10 ** 8;  // WBTC precision decimals
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    uint256 constant MAX_UINT = uint(-1);

    /*****************/
    /*** Utilities ***/
    /*****************/
    struct Token {
        address addr; // ERC20 Mainnet address
        uint256 slot; // Balance storage slot
        address orcl; // Chainlink oracle address
    }

    mapping (bytes32 => Token) tokens;

    struct TestObj {
        uint256 pre;
        uint256 post;
    }

    event Debug(string, uint256);
    event Debug(string, address);

    constructor() public { hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))); }

    /**************************************/
    /*** Actor/Multisig Setup Functions ***/
    /**************************************/
    function createBorrower()       public { bob = new Borrower(); }
    function createBorrowers()      public { bob = new Borrower(); ben = new Borrower(); bud = new Borrower(); }

    function createGovernor()       public { gov = new Governor(); }
    function createGovernors()      public { gov = new Governor(); fakeGov = new Governor(); }

    function createLP()             public { leo = new LP(); }
    function createLPs()            public { leo = new LP(); liz = new LP(); lex = new LP(); }

    function createPoolDelegate()   public { pat = new PoolDelegate(); }
    function createPoolDelegates()  public { pat = new PoolDelegate(); pam = new PoolDelegate(); }

    function createStaker()         public { sam = new Staker(); }
    function createStakers()        public { sam = new Staker(); sid = new Staker(); sue = new Staker(); }

    function createSecurityAdmin()  public { securityAdmin = new SecurityAdmin(); }

    function createEmergencyAdmin() public { emergencyAdmin = new EmergencyAdmin(); }

    function setUpActors() public {
        createBorrowers();
        createGovernors();
        createLPs();
        createPoolDelegates();
        createStakers();
        createSecurityAdmin();
        createEmergencyAdmin();
    }

    /**************************************/
    /*** Maple Contract Setup Functions ***/
    /**************************************/
    function createMpl()      public { mpl      = new MapleToken("MapleToken", "MAPL", USDC); }
    function createGlobals()  public { globals  = gov.createGlobals(address(mpl)); }
    function createTreasury() public { treasury = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals)); }
    function createBPool()    public { bPool    = IBPool(IBFactory(BPOOL_FACTORY).newBPool()); }

    function setUpGlobals() public {
        createMpl();
        createGlobals();
        createTreasury();
        createBPool();

        gov.setMapleTreasury(address(treasury));
        gov.setValidBalancerPool(address(bPool), true);
        gov.setCollateralAsset(WETH, true);
        gov.setLiquidityAsset(USDC, true);
        gov.setSwapOutRequired(1_000_000);
        gov.setPoolDelegateAllowlist(address(pat), true);
        gov.setPoolDelegateAllowlist(address(pam), true);
    }

    /**********************************/
    /*** Calculator Setup Functions ***/
    /**********************************/
    function createLateFeeCalc()   public { lateFeeCalc   = new LateFeeCalc(5); }
    function createPremiumCalc()   public { premiumCalc   = new PremiumCalc(500); }
    function createRepaymentCalc() public { repaymentCalc = new RepaymentCalc(); }

    function setUpCalcs() public {
        createLateFeeCalc();
        createPremiumCalc();
        createRepaymentCalc();

        gov.setCalc(address(repaymentCalc), true);
        gov.setCalc(address(lateFeeCalc),   true);
        gov.setCalc(address(premiumCalc),   true);
    }

    /********************************/
    /*** Factory Setup Functions ***/
    /********************************/
    function createPoolFactory()             public { poolFactory = new PoolFactory(address(globals)); }
    function createStakeLockerFactory()      public { slFactory   = new StakeLockerFactory(); }
    function createLiquidityLockerFactory()  public { llFactory   = new LiquidityLockerFactory(); }
    function createDebtLockerFactories()     public { dlFactory1  = new DebtLockerFactory(); dlFactory2  = new DebtLockerFactory(); }
    function createLoanFactory()             public { loanFactory = new LoanFactory(address(globals)); }
    function createCollateralLockerFactory() public { clFactory   = new CollateralLockerFactory(); }
    function createFundingLockerFactory()    public { flFactory   = new FundingLockerFactory(); }

    function setUpFactories() public {
        createPoolFactory();
        createStakeLockerFactory();
        createLiquidityLockerFactory();
        createDebtLockerFactories();
        createLoanFactory();
        createCollateralLockerFactory();
        createFundingLockerFactory();

        gov.setValidPoolFactory(address(poolFactory), true);
        gov.setValidSubFactory( address(poolFactory), address(slFactory),  true);
        gov.setValidSubFactory( address(poolFactory), address(llFactory),  true);
        gov.setValidSubFactory( address(poolFactory), address(dlFactory1), true);
        gov.setValidSubFactory( address(poolFactory), address(dlFactory2), true);

        gov.setValidLoanFactory(address(loanFactory), true);
        gov.setValidSubFactory( address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory( address(loanFactory), address(clFactory), true);
    }

    /**************************************/
    /*** Liquidity Pool Setup Functions ***/
    /**************************************/
    function setUpLiquidityPools() public {
        // Create and finalize Liquidity Pool
        pool = Pool(pat.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            uint256(-1)
        ));
        pat.approve(address(bPool), pool.stakeLocker(), uint(-1));
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)) / 2);
        pat.finalize(address(pool));
        pat.setOpenToPublic(address(pool), true);
    }

    /******************************/
    /*** Oracle Setup Functions ***/
    /******************************/
    function createWethOracle() public { wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this)); }
    function createWbtcOracle() public { wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this)); }
    function createUsdOracle()  public { usdOracle  = new UsdOracle(); }

    function setUpOracles() public {
        createWethOracle();
        createWbtcOracle();
        createUsdOracle();

        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));
    }

    /*************************************/
    /*** Balancer Pool Setup Functions ***/
    /*************************************/
    function setUpBalancerPool() public {
        // Mint 50m USDC into this account
        mint("USDC", address(this), 50_000_000 * USD);

        // Initialize MPL/USDC Balancer Pool and whitelist
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool());
        usdc.approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool),  MAX_UINT);
        bPool.bind(USDC,         50_000_000 * USD, 5 ether);  // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl),    100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight
        bPool.finalize();
        gov.setValidBalancerPool(address(bPool), true);

        // Transfer 50 BPTs each to pat and pam
        bPool.transfer(address(pat), bPool.balanceOf(address(this)) / 2);
        bPool.transfer(address(pam), bPool.balanceOf(address(this)));
    }
    /***  */

    /******************************/
    /*** Test Utility Functions ***/
    /******************************/

    function setUpTokens() public {
        tokens["USDC"].addr = USDC;
        tokens["USDC"].slot = 9;

        tokens["DAI"].addr = DAI;
        tokens["DAI"].slot = 2;
        tokens["DAI"].orcl = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

        tokens["WETH"].addr = WETH;
        tokens["WETH"].slot = 3;
        tokens["WETH"].orcl = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

        tokens["WBTC"].addr = WBTC;
        tokens["WBTC"].slot = 0;
        tokens["WBTC"].orcl = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    }

    // Manipulate mainnet ERC20 balance
    function mint(bytes32 symbol, address who, uint256 amt) public {
        address addr = tokens[symbol].addr;
        uint256 slot  = tokens[symbol].slot;
        uint256 bal = IERC20(addr).balanceOf(who);

        hevm.store(
            addr,
            keccak256(abi.encode(who, slot)), // Mint tokens
            bytes32(bal + amt)
        );

        assertEq(IERC20(addr).balanceOf(who), bal + amt); // Assert new balance
    }

    // Verify equality within accuracy decimals
    function withinPrecision(uint256 val0, uint256 val1, uint256 accuracy) public {
        uint256 diff  = val0 > val1 ? val0 - val1 : val1 - val0;
        if (diff == 0) return;

        uint256 denominator = val0 == 0 ? val1 : val0;
        bool check = ((diff * RAY) / denominator) < (RAY / 10 ** accuracy);

        if (!check){
            emit log_named_uint("Error: approx a == b not satisfied, accuracy digits ", accuracy);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }

    // Verify equality within difference
    function withinDiff(uint256 val0, uint256 val1, uint256 expectedDiff) public {
        uint actualDiff = val0 > val1 ? val0 - val1 : val1 - val0;
        bool check = actualDiff <= expectedDiff;

        if (!check) {
            emit log_named_uint("Error: approx a == b not satisfied, accuracy difference ", expectedDiff);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }

    function constrictToRange(uint256 val, uint256 min, uint256 max) public pure returns(uint256) {
        return constrictToRange(val, min, max, false);
    }

    function constrictToRange(uint256 val, uint256 min, uint256 max, bool nonZero) public pure returns(uint256) {
        return val == 0 && !nonZero ? 0 : val % (max - min) + min;
    }

    // function test_cheat_code_for_slot() public {
    //     address CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    //     uint256 i = 0;

    //     while(IERC20(CDAI).balanceOf(address(this)) == 0) {
    //         hevm.store(
    //             CDAI,
    //             keccak256(abi.encode(address(this), i)), // Mint tokens
    //             bytes32(uint256(100))
    //         );
    //         if(IERC20(CDAI).balanceOf(address(this)) == 100) {
    //             log_named_uint("slot", i);
    //         }
    //         i += 1;
    //     }
    //     // assertTrue(false);
    // }

    // // Make payment on any given Loan.
    // function makePayment(address _vault, address _borrower) public {

    //     // Create loanVault object and ensure it's accepting payments.
    //     Loan loanVault = Loan(_vault);
    //     assertEq(uint256(loanVault.loanState()), 1);  // Loan state: (1) Active

    //     // Warp to *300 seconds* before next payment is due
    //     hevm.warp(loanVault.nextPaymentDue() - 300);
    //     assertEq(block.timestamp, loanVault.nextPaymentDue() - 300);

    //     // Make payment.
    //     address _liquidityAsset = loanVault.liquidityAsset();
    //     (uint _amt,,,) = loanVault.getNextPayment();

    //     User(_borrower).approve(_liquidityAsset, _vault, _amt);

    //     assertTrue(ali.try_makePayment(_vault));
    // }
}
