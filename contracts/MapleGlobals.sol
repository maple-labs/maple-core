// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./interfaces/IPriceFeed.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/ISubFactory.sol";

interface AggregatorV3Interface {
  function latestRoundData() external view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

contract MapleGlobals {

    address immutable public BFactory;   // Official balancer pool factory.

    address public governor;             // Governor is responsible for management of global Maple variables
    address public mpl;                  // Maple Token is the ERC-2222 token for the Maple protocol
    address public mapleTreasury;        // Maple Treasury is the Treasury which all fees pass through for conversion, prior to distribution
    address public loanFactory;          // Loan vault factory (TODO: Need to handle multiple)
    address public poolFactory;          // Loan vault factory (TODO: Need to handle multiple)


    uint256 public gracePeriod;          // Represents the amount of time a borrower has to make a missed payment before a default can be triggered.
    uint256 public swapOutRequired;      // Represents the swap out amount required from staked assets for a Pool's liquidity asset, for default purposes.
    uint256 public unstakeDelay;         // Parameter for unstake delay, with relation to StakeLocker withdrawals.
    uint256 public drawdownGracePeriod;  // Amount of time to allow borrower to drawdown on their loan after funding period ends.
    uint256 public investorFee;          // Portion of drawdown that goes to pool delegates/investors
    uint256 public treasuryFee;          // Portion of drawdown that goes to treasury
    uint256 public extendedGracePeriod;  // Extended time period provided to the borrowers to clear the dues and during this period pool delegate are free to liquidate the loan.


    mapping(address => bool)    public isValidLoanAsset;        // Mapping of valid loan assets
    mapping(address => bool)    public isValidCollateralAsset;  // Mapping of valid collateral assets
    mapping(address => bool)    public isValidCalc;             // Mapping of valid calculator contracts
    mapping(address => bool)    public isValidPoolDelegate;     // Validation data structure for pool delegates (prevent invalid addresses from creating pools).
    
    // Determines the liquidation path of various assets in Loans and Treasury.
    // The value provided will determine whether or not to perform a bilateral or triangular swap on Uniswap.
    // For example, defaultUniswapPath[WETH][USDC] value would indicate what asset to convert WETH into before
    // conversion to USDC. If defaultUniswapPath[WETH][USDC] == USDC ... then the swap is bilateral and no middle
    // asset is swapped. If defaultUniswapPath[WETH][USDC] == WBTC ... then swap WETH for WBTC, then WBTC for USDC.
    mapping(address => mapping(address => address)) public defaultUniswapPath; 

    
    mapping(address => address) public assetPriceFeed;          // Mapping of asset, to the associated oracle price feed.
    mapping(address => address) public oracleFor;               // ChainLink oracle for a given asset.

    mapping(address => bool)                     public isValidPoolFactory;  // Mapping of valid pool factories.
    mapping(address => bool)                     public isValidLoanFactory;  // Mapping of valid loan factories.
    mapping(address => mapping(address => bool)) public validSubFactories;   // Mapping of valid sub factories.

    
    event CollateralAssetSet(address asset, uint256 decimals, string symbol, bool valid);
    event       LoanAssetSet(address asset, uint256 decimals, string symbol, bool valid);
    event  PriceFeedAssigned(address asset, address oracle);

    modifier isGovernor() {
        require(msg.sender == governor, "MapleGlobals:MSG_SENDER_NOT_GOVERNOR");
        _;
    }

    /**
        @dev    Constructor function.
        @param  _governor The administrator's address.
        @param  _mpl      The address of the ERC-2222 token for the Maple protocol.
        @param  _bFactory The official Balancer pool factory.
    */
    constructor(address _governor, address _mpl, address _bFactory) public {
        governor            = _governor;
        mpl                 = _mpl;
        gracePeriod         = 5 days;
        extendedGracePeriod = 5 days; // TODO how much?
        swapOutRequired     = 100;
        unstakeDelay        = 90 days;
        drawdownGracePeriod = 1 days;
        investorFee         = 50;
        treasuryFee         = 50;
        BFactory            = _bFactory;
    }

    /**
        @dev   Update the `extendedGracePeriod` variable.
        @param newExtendedGracePeriod New value of extendedGracePeriod.
     */
    function setExtendedGracePeriod(uint256 newExtendedGracePeriod) external isGovernor {
        extendedGracePeriod = newExtendedGracePeriod;
    }
    
    /**
        @dev   Update the valid pool factories mapping.
        @param poolFactory Address of loan factory.
        @param valid       The new bool value for validating poolFactory.
    */
    function setValidPoolFactory(address poolFactory, bool valid) external isGovernor {
        isValidPoolFactory[poolFactory] = valid;
    }

    /**
        @dev   Update the valid loan factories mapping.
        @param loanFactory Address of loan factory.
        @param valid       The new bool value for validating loanFactory.
    */
    function setValidLoanFactory(address loanFactory, bool valid) external isGovernor {
        isValidLoanFactory[loanFactory] = valid;
    }

    /**
        @dev    Set the validity of a subFactory as it relates to a superFactory.
        @param  superFactory The core factory (e.g. PoolFactory, LoanFactory)
        @param  subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory)
        @param  valid        The validity of subFactory within context of superFactory.
    */
    function setValidSubFactory(address superFactory, address subFactory, bool valid) external isGovernor {
        validSubFactories[superFactory][subFactory] = valid;
    }

    /**
        @dev    Set the path to swap an asset through Uniswap.
        @param  from The asset being swapped.
        @param  to   The final asset to receive.*
        @param  mid  The middle path. 
        
        * Set to == mid to enable a bilateral swap (single path swap).
          Set to != mid to enable a triangular swap (multi path swap).
    */
    function setDefaultUniswapPath(address from, address to, address mid) external isGovernor {
        defaultUniswapPath[from][to] = mid;
    }

    /**
        @dev    Check the validity of a subFactory as it relates to a superFactory.
        @param  superFactory The core factory (e.g. PoolFactory, LoanFactory)
        @param  subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory)
        @param  factoryType  The type expected for the subFactory.
    */
    function isValidSubFactory(address superFactory, address subFactory, uint8 factoryType) external returns(bool) {
        return validSubFactories[superFactory][subFactory] && ISubFactory(subFactory).factoryType() == factoryType;
    }

    /**
        @dev Update validity of pool delegate (those able to create pools).
        @param  delegate The address to manage permissions for.
        @param  valid    The new permissions of delegate.
    */
    function setPoolDelegateWhitelist(address delegate, bool valid) external isGovernor {
        isValidPoolDelegate[delegate] = valid;
    }

    /**
        @dev Update a price feed's oracle.
        @param  asset  The asset to update price for.
        @param  oracle The new oracle to use.
    */
    function assignPriceFeed(address asset, address oracle) external isGovernor {
        require(isValidLoanAsset[asset] || isValidCollateralAsset[asset], "MapleGlobals:PRICE_FEED_ASSET_NOT_WHITELISTED");
        assetPriceFeed[asset] = oracle;
        emit PriceFeedAssigned(asset, oracle);
    }

    /**
        @dev Get a price feed.
        @param  asset  The asset to fetch price for.
    */
    function getPrice(address asset) external view returns(uint) {
        return IPriceFeed(assetPriceFeed[asset]).price();
    }

    /**
        @dev Set the validity of an asset for collateral.
        @param asset The asset to assign validity to.
        @param valid The new validity of asset as collateral.
    */
    function setCollateralAsset(address asset, bool valid) external isGovernor {
        isValidCollateralAsset[asset] = valid;
        emit CollateralAssetSet(asset, IERC20Details(asset).decimals(), IERC20Details(asset).symbol(), valid);
    }

    /**
        @dev Governor can add a valid asset, used for borrowing.
        @param asset Address of the valid asset.
        @param valid Boolean
    */
    function setLoanAsset(address asset, bool valid) external isGovernor {
        isValidLoanAsset[asset] = valid;
        emit LoanAssetSet(asset, IERC20Details(asset).decimals(), IERC20Details(asset).symbol(), valid);
    }

    /**
        @dev Specifiy validity of a calculator contract.
        @param  calc  The calculator.
        @param  valid The validity of calc.
    */
    function setCalc(address calc, bool valid) public isGovernor {
        isValidCalc[calc] = valid;
    }

    /**
        @dev Governor can adjust investorFee (in basis points).
        @param _fee The fee, 50 = 0.50%
    */
    function setInvestorFee(uint256 _fee) public isGovernor {
        investorFee = _fee;
    }

    /**
        @dev Governor can adjust treasuryFee (in basis points).
        @param _fee The fee, 50 = 0.50%
    */
    function setTreasuryFee(uint256 _fee) public isGovernor {
        treasuryFee = _fee;
    }

    /**
        @dev Governor can set the MapleTreasury contract.
        @param _mapleTreasury The MapleTreasury contract.
    */
    function setMapleTreasury(address _mapleTreasury) public isGovernor {
        mapleTreasury = _mapleTreasury;
    }

    /**
        @dev Governor can adjust the grace period.
        @param _gracePeriod Number of seconds to set the grace period to.
    */
    function setGracePeriod(uint256 _gracePeriod) public isGovernor {
        gracePeriod = _gracePeriod;
    }

    /**
        @dev Governor can adjust the drawdown grace period.
        @param _drawdownGracePeriod Number of seconds to set the drawdown grace period to.
    */
    function setDrawdownGracePeriod(uint256 _drawdownGracePeriod) public isGovernor {
        drawdownGracePeriod = _drawdownGracePeriod;
    }

    /**
        @dev Governor can adjust the swap out amount required to finalize a pool.
        @param amt The new minimum swap out required.
    */
    function setSwapOutRequired(uint256 amt) public isGovernor {
        swapOutRequired = amt;
    }

    /**
        @dev Governor can specify a new governor.
        @param _newGovernor The address of new governor.
    */
    function setGovernor(address _newGovernor) public isGovernor {
        governor = _newGovernor;
    }

    /**
        @dev Governor can specify a new unstake delay value.
        @param _unstakeDelay The new unstake delay.
    */
    function setUnstakeDelay(uint256 _unstakeDelay) public isGovernor {
        unstakeDelay = _unstakeDelay;
    }

    /**
        @dev Fetch price for asset from ChainLink oracles.
        @param asset The asset to fetch price.
        @return The price of asset.
    */
    function getLatestPrice(address asset) public view returns (uint256) {
        address oracle = oracleFor[asset];
        (,int price,,,) = AggregatorV3Interface(oracle).latestRoundData();
        return uint256(price);
    }

    /**
        @dev Governor can specify a new unstake delay value.
        @param asset The new unstake delay.
        @param oracle The new unstake delay.
    */
    function setPriceOracle(address asset, address oracle) public isGovernor {
        oracleFor[asset] = oracle;
    }
}
