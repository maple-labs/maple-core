// SPDX-License-Identifier: AGPL-3.0-or-later
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

import "core/globals/v1/MapleGlobals.sol";
import "core/treasury/v1/MapleTreasury.sol";
import "module/maple-token/contracts/MapleToken.sol";

import "core/collateral-locker/v1/CollateralLockerFactory.sol";
import "core/debt-locker/v1/DebtLockerFactory.sol";
import "core/funding-locker/v1/FundingLockerFactory.sol";
import "core/liquidity-locker/v1/LiquidityLockerFactory.sol";
import "core/loan/v1/LoanFactory.sol";
import "core/mpl-rewards/v1/MplRewardsFactory.sol";
import "core/pool/v1/PoolFactory.sol";
import "core/stake-locker/v1/StakeLockerFactory.sol";

import "external-interfaces/IUniswapV2Factory.sol";
import "external-interfaces/IUniswapV2Pair.sol";
import "external-interfaces/IUniswapV2Router02.sol";

import "core/late-fee-calculator/v1/LateFeeCalc.sol";
import "core/premium-calculator/v1/PremiumCalc.sol";
import "core/repayment-calculator/v1/RepaymentCalc.sol";

import "core/chainlink-oracle/v1/ChainlinkOracle.sol";
import "core/usd-oracle/v1/UsdOracle.sol";

import "external-interfaces/IBPool.sol";
import "external-interfaces/IBFactory.sol";

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

    using SafeMath for uint256;

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
    MapleGlobals       globals;
    MapleToken             mpl;
    MapleTreasury     treasury;
    IBPool               bPool;
    MplRewards      mplRewards;
    IUniswapV2Pair uniswapPair;

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
    StakeLocker stakeLocker;
    StakeLocker stakeLocker2;

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
    address constant UNISWAP_V2_FACTORY   = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f; // Uniswap V2 factory.

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

    uint256 constant MAX_UINT = uint256(-1);

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
    event Debug(string, bool);

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
    function createMpl()      public { mpl      = new MapleToken("MapleToken", "MPL", USDC); }
    function createGlobals()  public { globals  = gov.createGlobals(address(mpl)); }
    function createTreasury() public { treasury = new MapleTreasury(address(mpl), USDC, UNISWAP_V2_ROUTER_02, address(globals)); }
    function createBPool()    public { bPool    = IBPool(IBFactory(BPOOL_FACTORY).newBPool()); }

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
        gov.setGlobalAdmin(address(emergencyAdmin));
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
        stakeLocker = StakeLocker(pool.stakeLocker());
        pat.approve(address(bPool), pool.stakeLocker(), uint256(-1));
        pat.stake(pool.stakeLocker(), bPool.balanceOf(address(pat)));
        pat.finalize(address(pool));
        pat.setOpenToPublic(address(pool), true);
    }

    function stakeAndFinalizePool(uint256 stakeAmt) public {
        stakeLocker = StakeLocker(pool.stakeLocker());
        pat.approve(address(bPool), pool.stakeLocker(), uint256(-1));
        pat.stake(pool.stakeLocker(), stakeAmt);
        pat.finalize(address(pool));
        pat.setOpenToPublic(address(pool), true);
    }

    function stakeAndFinalizePools(uint256 stakeAmt, uint256 stakeAmt2) public {
        stakeAndFinalizePool(stakeAmt);

        stakeLocker2 = StakeLocker(pool2.stakeLocker());
        pam.approve(address(bPool), pool2.stakeLocker(), uint256(-1));
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
    function createBalancerPool(uint256 usdcAmount, uint256 mplAmount) public {
        // Mint USDC into this account
        mint("USDC", address(this), usdcAmount);

        // Initialize MPL/USDC Balancer Pool and whitelist
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool());
        usdc.approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool),  MAX_UINT);
        bPool.bind(USDC,         usdcAmount, 5 ether);  // Bind USDC with 5 denormalization weight
        bPool.bind(address(mpl),  mplAmount, 5 ether);  // Bind  MPL with 5 denormalization weight
        bPool.finalize();
        gov.setValidBalancerPool(address(bPool), true);
    }
    // TODO: Update this and update tests to use realistic launch pool (waiting for pool fuzz merge)
    function createBalancerPool() public {
        createBalancerPool(1_550_000 * USD, 155_000 * WAD);
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

    function transferMoreBpts(address to, uint256 amt) public {
        bPool.transfer(to, amt);
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
        fakeGov.setGovMplRewards(mplRewards);                            // Used to assert failures
    }

    function createFarmers() public {
        fay = new Farmer(mplRewards, pool);
        fez = new Farmer(mplRewards, pool);
        fox = new Farmer(mplRewards, pool);
    }

    function setUpFarmers(uint256 amt1, uint256 amt2, uint256 amt3) public {
        createFarmers();

        mintFundsAndDepositIntoPool(fay, pool, amt1, amt1);
        mintFundsAndDepositIntoPool(fez, pool, amt2, amt2);
        mintFundsAndDepositIntoPool(fox, pool, amt3, amt3);
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
    function mint(bytes32 symbol, address account, uint256 amt) public {
        address addr = tokens[symbol].addr;
        uint256 slot  = tokens[symbol].slot;
        uint256 bal = IERC20(addr).balanceOf(account);

        hevm.store(
            addr,
            keccak256(abi.encode(account, slot)), // Mint tokens
            bytes32(bal + amt)
        );

        assertEq(IERC20(addr).balanceOf(account), bal + amt); // Assert new balance
    }

    function getDiff(uint256 val0, uint256 val1) internal pure returns (uint256 diff) {
        diff = val0 > val1 ? val0 - val1 : val1 - val0;
    }

    // Verify equality within accuracy decimals
    function withinPrecision(uint256 val0, uint256 val1, uint256 accuracy) public {
        uint256 diff = getDiff(val0, val1);
        if (diff == 0) return;

        uint256 denominator = val0 == 0 ? val1 : val0;
        bool check = ((diff * RAY) / denominator) < (RAY / 10 ** accuracy);

        if (check) return;

        emit log_named_uint("Error: approx a == b not satisfied, accuracy digits ", accuracy);
        emit log_named_uint("  Expected", val0);
        emit log_named_uint("    Actual", val1);
        fail(); 
    }

    // Verify equality within accuracy percentage (basis points)
    function withinPercentage(uint256 val0, uint256 val1, uint256 percentage) public {
        uint256 diff = getDiff(val0, val1);
        if (diff == 0) return;

        uint256 denominator = val0 == 0 ? val1 : val0;
        bool check = ((diff * RAY) / denominator) < percentage * RAY / 10_000;

        if (check) return;

        emit log_named_uint("Error: approx a == b not satisfied, accuracy digits ", percentage);
        emit log_named_uint("  Expected", val0);
        emit log_named_uint("    Actual", val1);
        fail();
    }

    // Verify equality within accuracy percentage (basis points)
    function withinPercentage(uint256 val0, uint256 val1, uint256 percentage) public {
        uint256 diff  = val0 > val1 ? val0 - val1 : val1 - val0;
        if (diff == 0) return;

        uint256 denominator = val0 == 0 ? val1 : val0;
        bool check = ((diff * RAY) / denominator) < percentage * RAY / 10_000;

        if (!check){
            emit log_named_uint("Error: approx a == b not satisfied, accuracy digits ", percentage);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }

    // Verify equality within difference
    function withinDiff(uint256 val0, uint256 val1, uint256 expectedDiff) public {
        uint256 actualDiff = getDiff(val0, val1);
        bool check = actualDiff <= expectedDiff;

        if (check) return;

        emit log_named_uint("Error: approx a == b not satisfied, accuracy digits ", expectedDiff);
        emit log_named_uint("  Expected", val0);
        emit log_named_uint("    Actual", val1);
        fail();
    }

    function constrictToRange(uint256 val, uint256 min, uint256 max) public pure returns (uint256) {
        return constrictToRange(val, min, max, false);
    }

    function constrictToRange(uint256 val, uint256 min, uint256 max, bool nonZero) public pure returns (uint256) {
        if      (val == 0 && !nonZero) return 0;
        else if (max == min)           return max;
        else                           return val % (max - min) + min;
    }

    function getFuzzedSpecs(
        uint256 apr,
        uint256 index,             // Random index for random payment interval
        uint256 numPayments,       // Used for termDays
        uint256 requestAmount,
        uint256 collateralRatio
    ) public pure returns (uint256[5] memory specs) {
        return getFuzzedSpecs(apr, index, numPayments, requestAmount, collateralRatio, 10_000 * USD, 10_000, 1E10 * USD);
    }

    function getFuzzedSpecs(
        uint256 apr,
        uint256 index,             // Random index for random payment interval
        uint256 numPayments,       // Used for termDays
        uint256 requestAmount,
        uint256 collateralRatio,
        uint256 minimumRequestAmt,
        uint256 maxCollateralRatio,
        uint256 maxRequestAmt
    ) public pure returns (uint256[5] memory specs) {
        uint16[10] memory paymentIntervalArray = [1, 2, 5, 7, 10, 15, 30, 60, 90, 360];
        numPayments = constrictToRange(numPayments, 5, 100, true);
        uint256 paymentIntervalDays = paymentIntervalArray[index % 10];  // TODO: Consider changing this approach
        uint256 termDays            = paymentIntervalDays * numPayments;

        specs = [
            constrictToRange(apr, 1, 10_000, true),                                   // APR between 0.01% and 100% (non-zero for test behavior)
            termDays,                                                                 // Fuzzed term days
            paymentIntervalDays,                                                      // Payment interval days from array
            constrictToRange(requestAmount, minimumRequestAmt, maxRequestAmt, true),  // 10k USD - 10b USD loans (non-zero) in general scenario
            constrictToRange(collateralRatio, 0, maxCollateralRatio)                  // Collateral ratio between 0 and maxCollateralRatio
        ];
    }

    function toApy(uint256 yield, uint256 stake, uint256 dTime) internal returns (uint256) {
        return yield * 10_000 * 365 days / stake / dTime;
    }

    // Function used to calculate theoretical allotments (e.g. interest for FDTs)
    function calcPortion(uint256 amt, uint256 totalClaim, uint256 totalAmt) internal pure returns (uint256) {
        return amt == uint256(0) ? uint256(0) : amt.mul(totalClaim).div(totalAmt);
    }

    function setUpRepayments(uint256 loanAmt, uint256 apr, uint16 index, uint16 numPayments, uint256 lateFee, uint256 premiumFee) public {
        uint16[10] memory paymentIntervalArray = [1, 2, 5, 7, 10, 15, 30, 60, 90, 360];

        uint256 paymentInterval = paymentIntervalArray[index % 10];
        uint256 termDays        = paymentInterval * (numPayments % 100);

        {
            // Mint "infinite" amount of USDC and deposit into pool
            mint("USDC", address(this), loanAmt);
            IERC20(USDC).approve(address(pool), uint256(-1));
            pool.deposit(loanAmt);

            // Create loan, fund loan, draw down on loan
            address[3] memory calcs = [address(repaymentCalc), address(lateFeeCalc), address(premiumCalc)];
            uint256[5] memory specs = [apr, termDays, paymentInterval, loanAmt, 2000];
            loan = bob.createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory),  specs, calcs);
        }

        assertTrue(pat.try_fundLoan(address(pool), address(loan),  address(dlFactory), loanAmt));

        {
            uint256 cReq = loan.collateralRequiredForDrawdown(loanAmt); // wETH required for 1_000 USDC drawdown on loan
            mint("WETH", address(bob), cReq);
            bob.approve(WETH, address(loan), cReq);
            bob.drawdown(address(loan), loanAmt);
        }
    }

    /*****************************/
    /*** Yield Farming Helpers ***/
    /*****************************/
    function setUpFarming(uint256 totalMpl, uint256 rewardsDuration) internal {
        mpl.transfer(address(gov), totalMpl);              // Transfer MPL to Governor
        gov.transfer(mpl, address(mplRewards), totalMpl);  // Transfer MPL to MplRewards
        gov.setRewardsDuration(rewardsDuration);
        gov.notifyRewardAmount(totalMpl);
    }

    function stakeIntoFarm(Farmer farmer, uint256 amt) internal{
        farmer.increaseCustodyAllowance(address(pool), address(mplRewards), amt);
        farmer.stake(amt); 
    }

    function setUpFarmingAndDeposit(uint256 totalMpl, uint256 rewardsDuration, uint256 amt1, uint256 amt2, uint256 amt3) internal {
        setUpFarming(totalMpl, rewardsDuration);

        stakeIntoFarm(fay, amt1);
        stakeIntoFarm(fez, amt2);
        stakeIntoFarm(fox, amt3);
    }

    /********************/
    /*** Pool Helpers ***/
    /********************/
    function finalizePool(Pool pool, PoolDelegate del, bool openToPublic) internal {
        del.approve(address(bPool), pool.stakeLocker(), MAX_UINT);
        del.stake(pool.stakeLocker(), bPool.balanceOf(address(del)) / 2);

        del.finalize(address(pool));
        if (openToPublic) del.setOpenToPublic(address(pool), true);
    }

    function mintFundsAndDepositIntoPool(LP lp, Pool pool, uint256 mintAmt, uint256 liquidityAmt) internal {
        if (mintAmt > uint256(0)) {
            mint("USDC", address(lp), mintAmt);
        }

        lp.approve(USDC, address(pool), MAX_UINT);
        lp.deposit(address(pool), liquidityAmt); 
    }

    function drawdown(Loan loan, Borrower bow, uint256 usdDrawdownAmt) internal {
        uint256 cReq = loan.collateralRequiredForDrawdown(usdDrawdownAmt); // wETH required for `usdDrawdownAmt` USDC drawdown on loan
        mint("WETH", address(bow), cReq);
        bow.approve(WETH, address(loan),  cReq);
        bow.drawdown(address(loan),  usdDrawdownAmt);
    }

    function doPartialLoanPayment(Loan loan, Borrower bow) internal returns (uint256 amt) {
        (amt,,,,) = loan.getNextPayment(); // USDC required for next payment of loan
        mint("USDC", address(bow), amt);
        bow.approve(USDC, address(loan),  amt);
        bow.makePayment(address(loan));
    }

    function doFullLoanPayment(Loan loan, Borrower bow) internal {
        (uint256 amt,,) = loan.getFullPayment(); // USDC required for full payment of loan
        mint("USDC", address(bow), amt);
        bow.approve(USDC, address(loan),  amt);
        bow.makeFullPayment(address(loan));
    }

    function setUpLoanMakeOnePaymentAndDefault() public returns (uint256 interestPaid) {
        // Fund the pool
        mint("USDC", address(leo), 20_000_000 * USD);
        leo.approve(USDC, address(pool), MAX_UINT);
        leo.deposit(address(pool), 10_000_000 * USD);

        // Fund the loan
        pat.fundLoan(address(pool), address(loan), address(dlFactory), 1_000_000 * USD);
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
        uint256 defaultGracePeriod = globals.defaultGracePeriod();
        hevm.warp(start + nextPaymentDue + defaultGracePeriod + 1);

        // Trigger default
        pat.triggerDefault(address(pool), address(loan), address(dlFactory));
    }

    function make_withdrawable(LP investor, Pool pool) internal {
        uint256 currentTime = block.timestamp;
        assertTrue(investor.try_intendToWithdraw(address(pool)));
        assertEq(pool.withdrawCooldown(address(investor)), currentTime, "Incorrect value set");
        hevm.warp(currentTime + globals.lpCooldownPeriod());
    }

    function setUpUniswapMplUsdcPool(uint256 mplDesiredAmt, uint256 usdcDesiredAmt) internal {
        // Mint USDC into this account
        mint("USDC", address(this), usdcDesiredAmt);

        // Initialize MPL/USDC Uniswap Pool
        uniswapPair = IUniswapV2Pair(IUniswapV2Factory(UNISWAP_V2_FACTORY).createPair(address(mpl), address(usdc)));
        usdc.approve(UNISWAP_V2_ROUTER_02, MAX_UINT);
        mpl.approve(UNISWAP_V2_ROUTER_02,  MAX_UINT);
        // passing the same value of amountAMin, amountBMin to mplDesiredAmt & usdcDesiredAmt respectively as those
        // values will never gonna be in use for the initial addition of the liquidity.
        IUniswapV2Router02(UNISWAP_V2_ROUTER_02).addLiquidity(address(mpl), address(usdc), mplDesiredAmt, usdcDesiredAmt, mplDesiredAmt, usdcDesiredAmt, address(gov), now + 10 minutes);
    }

    /***********************/
    /*** Staking Helpers ***/
    /***********************/
    function make_unstakeable(Staker staker, StakeLocker stakeLocker) internal {
        uint256 currentTime = block.timestamp;
        assertTrue(staker.try_intendToUnstake(address(stakeLocker)));
        assertEq(stakeLocker.unstakeCooldown(address(staker)), currentTime, "Incorrect value set");
        hevm.warp(currentTime + globals.stakerCooldownPeriod());
    }

    function toWad(uint256 amt) internal view returns (uint256) {
        return amt.mul(WAD).div(USD);
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
}
