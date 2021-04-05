// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./user/Borrower.sol";
import "./user/Commoner.sol";
import "./user/Farmer.sol";
import "./user/Holder.sol";
import "./user/LP.sol";
import "./user/PoolDelegate.sol";
import "./user/Staker.sol";

import "./user/Governor.sol";
import "./user/SecurityAdmin.sol";
import "./user/EmergencyAdmin.sol";

import "../MapleGlobals.sol";
import "../MapleTreasury.sol";
import "module/maple-token/contracts/MapleToken.sol";

import "../CollateralLockerFactory.sol";
import "../DebtLockerFactory.sol";
import "../FundingLockerFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../LoanFactory.sol";
import "../MplRewardsFactory.sol";
import "../PoolFactory.sol";
import "../StakeLockerFactory.sol";

import "../LateFeeCalc.sol";
import "../PremiumCalc.sol";
import "../RepaymentCalc.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/IBFactory.sol";
import "../interfaces/IStakeLocker.sol";

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

    Commoner      cam;

    Farmer        fay;
    Farmer        fez;
    Farmer        fox;

    Holder        hal;
    Holder        hue;

    LP            leo;
    LP            liz;
    LP            lex;
    LP            lee;

    PoolDelegate  pat;
    PoolDelegate  pam;

    Staker        sam;
    Staker        sid;
    Staker        sue;

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
    address[3]             calcs;

    /*****************/
    /*** Factories ***/
    /*****************/
    CollateralLockerFactory          clFactory;
    DebtLockerFactory                dlFactory;
    DebtLockerFactory               dlFactory2;
    FundingLockerFactory             flFactory;
    LiquidityLockerFactory           llFactory;
    LoanFactory                    loanFactory;
    PoolFactory                    poolFactory;
    StakeLockerFactory               slFactory;
    MplRewardsFactory        mplRewardsFactory;

    /***********************/
    /*** Maple Contracts ***/
    /***********************/
    MapleGlobals      globals;
    MapleToken            mpl;
    MapleTreasury    treasury;
    IBPool              bPool;
    MplRewards     mplRewards;

    /***************/
    /*** Oracles ***/
    /***************/
    ChainlinkOracle  wethOracle;
    ChainlinkOracle  wbtcOracle;
    ChainlinkOracle   daiOracle;
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

    /***************/
    /*** Lockers ***/
    /***************/
    IStakeLocker stakeLocker;
    IStakeLocker stakeLocker2;

    /**********************************/
    /*** Mainnet Contract Addresses ***/
    /**********************************/
    address constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC  = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH  = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC  = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant CDAI  = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    IERC20 constant dai  = IERC20(DAI);
    IERC20 constant usdc = IERC20(USDC);
    IERC20 constant weth = IERC20(WETH);
    IERC20 constant wbtc = IERC20(WBTC);

    address constant BPOOL_FACTORY        = 0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd; // Balancer pool factory
    address constant UNISWAP_V2_ROUTER_02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router

    /*****************/
    /*** Constants ***/
    /*****************/
    uint8 public constant CL_FACTORY = 0;  // Factory type of `CollateralLockerFactory`.
    uint8 public constant DL_FACTORY = 1;  // Factory type of `DebtLockerFactory`.
    uint8 public constant FL_FACTORY = 2;  // Factory type of `FundingLockerFactory`.
    uint8 public constant LL_FACTORY = 3;  // Factory type of `LiquidityLockerFactory`.
    uint8 public constant SL_FACTORY = 4;  // Factory type of `StakeLockerFactory`.

    uint8 public constant INTEREST_CALC_TYPE = 10;  // Calc type of `RepaymentCalc`.
    uint8 public constant LATEFEE_CALC_TYPE  = 11;  // Calc type of `LateFeeCalc`.
    uint8 public constant PREMIUM_CALC_TYPE  = 12;  // Calc type of `PremiumCalc`.

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
    event Debug(string,    bool);

    constructor() public { hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))); }

    /**************************************/
    /*** Actor/Multisig Setup Functions ***/
    /**************************************/
    function createBorrower()       public { bob = new Borrower(); }
    function createBorrowers()      public { bob = new Borrower(); ben = new Borrower(); bud = new Borrower(); }

    function createCommoner()       public { cam = new Commoner(); }

    function createHolder()         public { hal = new Holder(); }
    function createHolders()        public { hal = new Holder(); hue = new Holder(); }

    function createLP()             public { leo = new LP(); }
    function createLPs()            public { leo = new LP(); liz = new LP(); lex = new LP(); lee = new LP(); }

    function createPoolDelegate()   public { pat = new PoolDelegate(); }
    function createPoolDelegates()  public { pat = new PoolDelegate(); pam = new PoolDelegate(); }

    function createStaker()         public { sam = new Staker(); }
    function createStakers()        public { sam = new Staker(); sid = new Staker(); sue = new Staker(); }

    function createGovernor()       public { gov = new Governor(); }
    function createGovernors()      public { gov = new Governor(); fakeGov = new Governor(); }

    function createSecurityAdmin()  public { securityAdmin = new SecurityAdmin(); }

    function createEmergencyAdmin() public { emergencyAdmin = new EmergencyAdmin(); }

    function setUpPoolDelegate() public { 
        createPoolDelegate(); 
        gov.setPoolDelegateAllowlist(address(pat), true); 
    } 

    function setUpPoolDelegates() public {
        createPoolDelegates();
        gov.setPoolDelegateAllowlist(address(pat), true);
        gov.setPoolDelegateAllowlist(address(pam), true);
    }

    function setUpActors() public {
        setUpPoolDelegates();
        createBorrowers();
        createCommoner();
        createHolders();
        createLPs();
        createStakers();
    }

    /**************************************/
    /*** Maple Contract Setup Functions ***/
    /**************************************/
    function createMpl()               public { mpl               = new MapleToken("MapleToken", "MAPL", USDC); }
    function createGlobals()           public { globals           = gov.createGlobals(address(mpl)); }
    function createTreasury()          public { treasury          = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals)); }
    function createBPool()             public { bPool             = IBPool(IBFactory(BPOOL_FACTORY).newBPool()); }
    
    function setUpMplRewardsFactory() public { 
        mplRewardsFactory = gov.createMplRewardsFactory(); 
        fakeGov.setGovMplRewardsFactory(mplRewardsFactory); 
    }

    function setUpGlobals() public {
        createGovernors();
        createSecurityAdmin();
        createEmergencyAdmin();
        createMpl();
        createGlobals();
        createTreasury();
        createBPool();

        gov.setMapleTreasury(address(treasury));
        gov.setAdmin(address(emergencyAdmin));
        gov.setDefaultUniswapPath(WBTC, USDC, WETH);
        gov.setGovTreasury(treasury);
        fakeGov.setGovTreasury(treasury);
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

        calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];
    }

    /********************************/
    /*** Factory Setup Functions ***/
    /********************************/
    function createPoolFactory()             public { poolFactory = new PoolFactory(address(globals)); }
    function createStakeLockerFactory()      public { slFactory   = new StakeLockerFactory(); }
    function createLiquidityLockerFactory()  public { llFactory   = new LiquidityLockerFactory(); }
    function createDebtLockerFactories()     public { dlFactory   = new DebtLockerFactory(); dlFactory2  = new DebtLockerFactory(); }
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
        gov.setValidSubFactory( address(poolFactory), address(dlFactory),  true);
        gov.setValidSubFactory( address(poolFactory), address(dlFactory2), true);

        gov.setValidLoanFactory(address(loanFactory), true);
        gov.setValidSubFactory( address(loanFactory), address(flFactory), true);
        gov.setValidSubFactory( address(loanFactory), address(clFactory), true);
    }

    /**************************************/
    /*** Liquidity Pool Setup Functions ***/
    /**************************************/
    function createLiquidityPool() public {
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
    }

    function createLiquidityPools() public {
        createLiquidityPool();
        pool2 = Pool(pam.createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            7500,
            50,
            MAX_UINT // liquidityCap value
        ));
    }

    function setUpLiquidityPool() public {
        createLiquidityPool();
        stakeLocker = IStakeLocker(pool.stakeLocker());
        pat.approve(address(bPool), pool.stakeLocker(), uint(-1));
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)));
        pat.finalize(address(pool));
        pat.setOpenToPublic(address(pool), true);
    }

    function stakeAndFinalizePool(uint256 stakeAmt) public {
        stakeLocker = IStakeLocker(pool.stakeLocker());
        pat.approve(address(bPool), pool.stakeLocker(), uint(-1));
        pat.stake(pool.stakeLocker(), stakeAmt);
        pat.finalize(address(pool));
        pat.setOpenToPublic(address(pool), true);
    }

    function stakeAndFinalizePools(uint256 stakeAmt, uint256 stakeAmt2) public {
        stakeAndFinalizePool(stakeAmt);

        stakeLocker2 = IStakeLocker(pool2.stakeLocker());
        pam.approve(address(bPool), pool2.stakeLocker(), uint(-1));
        pam.stake(pool2.stakeLocker(), stakeAmt2);
        pam.finalize(address(pool2));
        pam.setOpenToPublic(address(pool2), true);
    }

    function stakeAndFinalizePool() public {
        stakeAndFinalizePool(bPool.balanceOf(address(pat)));
    }

    function stakeAndFinalizePools() public {
        stakeAndFinalizePools(bPool.balanceOf(address(pat)), bPool.balanceOf(address(pam)));
    }

    function setUpLiquidityPools() public {
        createLiquidityPools();
        stakeAndFinalizePools();
    }

    /******************************/
    /*** Oracle Setup Functions ***/
    /******************************/
    function createWethOracle() public { wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(securityAdmin)); }
    function createWbtcOracle() public { wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(securityAdmin)); }
    function createDaiOracle()  public { daiOracle  = new ChainlinkOracle(tokens["DAI"].orcl,  DAI,  address(securityAdmin)); }
    function createUsdOracle()  public { usdOracle  = new UsdOracle(); }

    function setUpOracles() public {
        createWethOracle();
        createWbtcOracle();
        createDaiOracle();
        createUsdOracle();

        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(DAI,  address(daiOracle));
        gov.setPriceOracle(USDC, address(usdOracle));
    }

    /*************************************/
    /*** Balancer Pool Setup Functions ***/
    /*************************************/
    function createBalancerPool() public {
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
    }

    function setUpBalancerPool() public {
        createBalancerPool(); 
        transferBptsToPoolDelegates();
    }

    function setUpBalancerPoolForStakers() public {
        createBalancerPool(); 
        transferBptsToPoolDelegateAndStakers();
    }

    function setUpBalancerPoolForPools() public {
        createBalancerPool(); 
        transferBptsToPoolDelegatesAndStakers();
    }

    function transferBptsToPoolDelegates() public {
        bPool.transfer(address(pat), 50 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(pam), 50 * WAD);  // Give PD a balance of BPTs to finalize pool
    }

    function transferBptsToPoolDelegateAndStakers() public {
        bPool.transfer(address(pat), 50 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(sam), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
        bPool.transfer(address(sid), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
    }

    function transferBptsToPoolDelegatesAndStakers() public {
        bPool.transfer(address(pat), 25 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(pam), 25 * WAD);  // Give PD a balance of BPTs to finalize pool
        bPool.transfer(address(sam), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
        bPool.transfer(address(sid), 25 * WAD);  // Give staker a balance of BPTs to stake against finalized pool
    }

    /****************************/
    /*** Loan Setup Functions ***/
    /****************************/
    function createLoan() public {
        uint256[5] memory specs = [500, 180, 30, uint256(1000 * USD), 2000];
        loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
    }
    function createLoan(uint256[5] memory specs) public {
        loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
    }
    function createLoans() public {
        uint256[5] memory specs = [500, 180, 30, uint256(1000 * USD), 2000];
        loan  = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan2 = ben.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
        loan3 = bud.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs);
    }

    /*************************************/
    /*** Yield Farming Setup Functions ***/
    /*************************************/
    function setUpMplRewards() public {
        mplRewards = gov.createMplRewards(address(mpl), address(pool)); 
        gov.setExemptFromTransferRestriction(address(mplRewards), true); // Set in globals so that depDate is not affected on stake/unstake
        fakeGov.setGovMplRewards(mplRewards);                            // Used to assert failures 
    }

    function setUpFarmers() public {
        fay = new Farmer(mplRewards, pool);
        fez = new Farmer(mplRewards, pool);
        fox = new Farmer(mplRewards, pool);

        mint("USDC", address(fay), 1000 * USD);
        mint("USDC", address(fez), 1000 * USD);
        mint("USDC", address(fox), 1000 * USD);

        fay.approve(USDC, address(pool), MAX_UINT);
        fez.approve(USDC, address(pool), MAX_UINT);
        fox.approve(USDC, address(pool), MAX_UINT);

        fay.deposit(address(pool), 1000 * USD);  // Mints 1000 * WAD of Pool FDT tokens
        fez.deposit(address(pool), 1000 * USD);  // Mints 1000 * WAD of Pool FDT tokens
        fox.deposit(address(pool), 1000 * USD);  // Mints 1000 * WAD of Pool FDT tokens
    }

    /******************************/
    /*** Test Utility Functions ***/
    /******************************/

    function setUpTokens() public {
        gov.setLiquidityAsset(DAI,   true);
        gov.setLiquidityAsset(USDC,  true);
        gov.setCollateralAsset(DAI,  true);
        gov.setCollateralAsset(USDC, true);
        gov.setCollateralAsset(WETH, true);
        gov.setCollateralAsset(WBTC, true);

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
