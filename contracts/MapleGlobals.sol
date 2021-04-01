// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./interfaces/IERC20Details.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ISubFactory.sol";

interface ICalc { function calcType() external view returns (uint8); }

/// @title MapleGlobals maintains a central source of parameters and allowlists for the Maple protocol.
contract MapleGlobals {

    address public immutable mpl;         // Maple Token is the ERC-2222 token for the Maple protocol

    address public pendingGovernor;       // Governor that is declared for transfer, must be accepted for transfer to take effect
    address public governor;              // Governor is responsible for management of global Maple variables
    address public mapleTreasury;         // Maple Treasury is the Treasury which all fees pass through for conversion, prior to distribution
    address public admin;                 // Admin of the whole network, has the power to switch off/on the functionality of entire protocol

    uint256 public gracePeriod;           // Represents the amount of time a borrower has to make a missed payment before a default can be triggered
    uint256 public swapOutRequired;       // Represents minimum amount of Pool cover that a Pool Delegate has to provide before they can finalize a Pool
    uint256 public drawdownGracePeriod;   // Amount of time to allow borrower to drawdown on their loan after funding period ends
    uint256 public investorFee;           // Portion of drawdown that goes to Pool Delegates/individual lenders
    uint256 public treasuryFee;           // Portion of drawdown that goes to MapleTreasury
    uint256 public maxSwapSlippage;       // Maximum amount of slippage for Uniswap transactions
    uint256 public minLoanEquity;         // Minimum amount of LoanFDTs required to trigger liquidations (basis points percentage of totalSupply)
    uint256 public stakerCooldownPeriod;  // Period (in secs) after which stakers are allowed to unstake  their BPTs  from the StakeLocker contract
    uint256 public lpCooldownPeriod;      // Period (in secs) after which LPs     are allowed to withdraw their funds from the Pool contract
    uint256 public stakerUnstakeWindow;   // Window of time (in secs) after `stakerCooldownPeriod` that a user has to withdraw before their intent to unstake  is invalidated
    uint256 public lpWithdrawWindow;      // Window of time (in secs) after `lpCooldownPeriod`     that a user has to withdraw before their intent to withdraw is invalidated


    bool public protocolPaused;  // Switch to pause the functionality of the entire protocol

    mapping(address => bool) public isValidLiquidityAsset;   // Mapping of valid liquidityAssets
    mapping(address => bool) public isValidCollateralAsset;  // Mapping of valid collateralAssets
    mapping(address => bool) public validCalcs;              // Mapping of valid calculator contracts
    mapping(address => bool) public isValidPoolDelegate;     // Validation data structure for Pool Delegates (prevent invalid addresses from creating pools)
    mapping(address => bool) public isValidMplRewards;       // Validation of if address is MplRewards contract used for MPL liquidity mining programs
    mapping(address => bool) public isValidBalancerPool;     // Validation of if address is a Balancer Pool that Maple has approved for BPT staking
    
    // Determines the liquidation path of various assets in Loans and Treasury.
    // The value provided will determine whether or not to perform a bilateral or triangular swap on Uniswap.
    // For example, defaultUniswapPath[WBTC][USDC] value would indicate what asset to convert WBTC into before
    // conversion to USDC. If defaultUniswapPath[WBTC][USDC] == USDC, then the swap is bilateral and no middle
    // asset is swapped.   If defaultUniswapPath[WBTC][USDC] == WETH, then swap WBTC for WETH, then WETH for USDC.
    mapping(address => mapping(address => address)) public defaultUniswapPath;

    mapping(address => address) public oracleFor;  // Chainlink oracle for a given asset

    mapping(address => bool)                     public isValidPoolFactory;  // Mapping of valid pool factories
    mapping(address => bool)                     public isValidLoanFactory;  // Mapping of valid loan factories
    mapping(address => mapping(address => bool)) public validSubFactories;   // Mapping of valid sub factories
    
    event CollateralAssetSet(address asset, uint256 decimals, string symbol, bool valid);
    event  LiquidityAssetSet(address asset, uint256 decimals, string symbol, bool valid);
    event          OracleSet(address asset, address oracle);
    event      MplRewardsSet(address mplRewards, bool valid);
    event    BalancerPoolSet(address balancerPool,   bool valid);
    event PendingGovernorSet(address pendingGovernor);
    event   GovernorAccepted(address governor);
    event    GlobalsParamSet(bytes32 indexed which, uint256 value);
    event  GlobalsAddressSet(bytes32 indexed which, address addr);
    event     ProtocolPaused(bool pause);

    modifier isGovernor() {
        require(msg.sender == governor, "MapleGlobals:MSG_SENDER_NOT_GOVERNOR");
        _;
    }

    /**
        @dev    Constructor function.
        @param  _governor Address of Governor
        @param  _mpl      Address of the ERC-2222 token for the Maple protocol
        @param  _admin    Address that takes care of protocol security switch 
    */
    constructor(address _governor, address _mpl, address _admin) public {
        governor             = _governor;
        mpl                  = _mpl;
        gracePeriod          = 5 days;
        swapOutRequired      = 10_000;     // $10,000 of Pool cover
        drawdownGracePeriod  = 10 days;
        investorFee          = 50;         // 0.5%
        treasuryFee          = 50;         // 0.5%
        maxSwapSlippage      = 1000;       // 10 %
        minLoanEquity        = 2000;       // 20 %
        admin                = _admin;
        stakerCooldownPeriod = 10 days;
        lpCooldownPeriod     = 10 days;
        stakerUnstakeWindow  = 2 days;     // Staker cooldown period must be set manually by the governor
        lpWithdrawWindow     = 2 days;     // LP     cooldown period must be set manually by the governor
    }

    /************************/
    /*** Setter Functions ***/
    /************************/

    /**
        @dev Update the `stakerCooldownPeriod` state variable. This change will affect existing cool down period for the stakers who already applied for the unstake.
        @param newCooldownPeriod New value for the cool down period.
     */
        function setStakerCooldownPeriod(uint256 newCooldownPeriod) external isGovernor {
        stakerCooldownPeriod = newCooldownPeriod;
        emit GlobalsParamSet("STAKER_COOLDOWN_PERIOD", newCooldownPeriod);
    }

    /**
        @dev Update the `lpCooldownPeriod` state variable. This change will affect existing cool down period for the LPs who already applied for the withdraw.
        @param newCooldownPeriod New value for the cool down period.
     */
    function setLpCooldownPeriod(uint256 newCooldownPeriod) external isGovernor {
        lpCooldownPeriod = newCooldownPeriod;
        emit GlobalsParamSet("LP_COOLDOWN_PERIOD", newCooldownPeriod);
    }

    /**
        @dev Update the `stakerUnstakeWindow` state variable. TODO: "This change" update
        @param newUnstakeWindow New value for the unstake window.
     */
    function setStakerUnstakeWindow(uint256 newUnstakeWindow) external isGovernor {
        stakerUnstakeWindow = newUnstakeWindow;
        emit GlobalsParamSet("STAKER_UNSTAKE_WINDOW", newUnstakeWindow);
    }

    /**
        @dev Update the `lpWithdrawWindow` state variable. TODO: "This change" update
        @param newLpWithdrawWindow New value for the withdraw window.
     */
    function setLpWithdrawWindow(uint256 newLpWithdrawWindow) external isGovernor {
        lpWithdrawWindow = newLpWithdrawWindow;
        emit GlobalsParamSet("LP_WITHDRAW_WINDOW", newLpWithdrawWindow);
    }

    /**
        @dev Update the allowed Uniswap slippage percentage, in basis points. Only Governor can call.
        @param newSlippage New slippage percentage (in basis points)
     */
    function setMaxSwapSlippage(uint256 newSlippage) external isGovernor {
        _checkPercentageRange(newSlippage);
        maxSwapSlippage = newSlippage;
        emit GlobalsParamSet("MAX_SWAP_SLIPPAGE", newSlippage);
    }

    /**
      @dev Set admin.
      @param newAdmin New admin address
     */
    function setAdmin(address newAdmin) external {
        require(msg.sender == governor && admin != address(0), "MapleGlobals:UNAUTHORIZED");
        require(!protocolPaused, "MapleGlobals:PROCOTOL_PAUSED");
        admin = newAdmin;
    }

    /**
        @dev Update the valid MplRewards mapping. Only Governor can call.
        @param mplRewards Address of `MplRewards` contract.
        @param valid      The new bool value for validating mplRewards.
    */
    function setValidMplRewards(address mplRewards, bool valid) external isGovernor {
        isValidMplRewards[mplRewards] = valid;
        emit MplRewardsSet(mplRewards, valid);
    }

    /**
        @dev Update the valid Balancer Pool mapping. Only Governor can call.
        @param balancerPool Address of Balancer Pool contract.
        @param valid        The new bool value for validating Balancer Pool.
    */
    function setValidBalancerPool(address balancerPool, bool valid) external isGovernor {
        isValidBalancerPool[balancerPool] = valid;
        emit BalancerPoolSet(balancerPool, valid);
    }
    
    /**
      @dev Pause/unpause the protocol. Only admin user can call.
      @param pause Boolean flag to switch externally facing functionality in the protocol on/off
     */
    function setProtocolPause(bool pause) external {
        require(msg.sender == admin, "MapleGlobals:UNAUTHORIZED");
        protocolPaused = pause;
        emit ProtocolPaused(pause);
    }
    
    /**
        @dev Update the valid PoolFactory mapping. Only Governor can call.
        @param poolFactory Address of PoolFactory
        @param valid       The new bool value for validating poolFactory
    */
    function setValidPoolFactory(address poolFactory, bool valid) external isGovernor {
        isValidPoolFactory[poolFactory] = valid;
    }

    /**
        @dev Update the valid LoanFactory mapping. Only Governor can call.
        @param loanFactory Address of LoanFactory
        @param valid       The new bool value for validating loanFactory.
    */
    function setValidLoanFactory(address loanFactory, bool valid) external isGovernor {
        isValidLoanFactory[loanFactory] = valid;
    }

    /**
        @dev Set the validity of a subFactory as it relates to a superFactory. Only Governor can call.
        @param superFactory The core factory (e.g. PoolFactory, LoanFactory)
        @param subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory)
        @param valid        The validity of subFactory within context of superFactory
    */
    function setValidSubFactory(address superFactory, address subFactory, bool valid) external isGovernor {
        require(isValidLoanFactory[superFactory] || isValidPoolFactory[superFactory], "MapleGlobals:SUPER_FACTORY_NOT_VALID");
        validSubFactories[superFactory][subFactory] = valid;
    }

    /**
        @dev Set the path to swap an asset through Uniswap. Only Governor can call.
        @param from Asset being swapped
        @param to   Final asset to receive **
        @param mid  Middle asset
        
        ** Set to == mid to enable a bilateral swap (single path swap).
           Set to != mid to enable a triangular swap (multi path swap).
    */
    function setDefaultUniswapPath(address from, address to, address mid) external isGovernor {
        defaultUniswapPath[from][to] = mid;
    }

    /**
        @dev Update validity of Pool Delegate (those allowed to create Pools). Only Governor can call.
        @param delegate Address to manage permissions for
        @param valid    New permissions of address
    */
    function setPoolDelegateAllowlist(address delegate, bool valid) external isGovernor {
        isValidPoolDelegate[delegate] = valid;
    }
    /**
        @dev Set the validity of an asset for collateral. Only Governor can call.
        @param asset The asset to assign validity to
        @param valid The new validity of asset as collateral
    */
    function setCollateralAsset(address asset, bool valid) external isGovernor {
        isValidCollateralAsset[asset] = valid;
        emit CollateralAssetSet(asset, IERC20Details(asset).decimals(), IERC20Details(asset).symbol(), valid);
    }

    /**
        @dev Set the validity of an asset for loans/liquidity in Pools. Only Governor can call.
        @param asset Address of the valid asset
        @param valid The new validity of asset for loans/liquidity in Pools
    */
    function setLiquidityAsset(address asset, bool valid) external isGovernor {
        isValidLiquidityAsset[asset] = valid;
        emit LiquidityAssetSet(asset, IERC20Details(asset).decimals(), IERC20Details(asset).symbol(), valid);
    }

    /**
        @dev Specifiy validity of a calculator contract. Only Governor can call.
        @param  calc  Calculator address
        @param  valid Validity of calculator
    */
    function setCalc(address calc, bool valid) external isGovernor {
        validCalcs[calc] = valid;
    }

    /**
        @dev Adjust investorFee (in basis points). Only Governor can call.
        @param _fee The fee, e.g., 50 = 0.50%
    */
    function setInvestorFee(uint256 _fee) external isGovernor {
        _checkPercentageRange(_fee);
        require(_fee + treasuryFee <= 10_000, "MapleGlobals:INVALID_INVESTOR_FEE");
        investorFee = _fee;
        emit GlobalsParamSet("INVESTOR_FEE", _fee);
    }

    /**
        @dev Adjust treasuryFee (in basis points). Only Governor can call.
        @param _fee The fee, e.g., 50 = 0.50%
    */
    function setTreasuryFee(uint256 _fee) external isGovernor {
        _checkPercentageRange(_fee);
        require(_fee + investorFee <= 10_000, "MapleGlobals:INVALID_TREASURY_FEE");
        treasuryFee = _fee;
        emit GlobalsParamSet("TREASURY_FEE", _fee);
    }

    /**
        @dev Set the MapleTreasury contract. Only Governor can call.
        @param _mapleTreasury New MapleTreasury address
    */
    function setMapleTreasury(address _mapleTreasury) external isGovernor {
        require(_mapleTreasury != address(0), "MapleGlobals:ZERO_ADDRESS");
        mapleTreasury = _mapleTreasury;
        emit GlobalsAddressSet("MAPLE_TREASURY", _mapleTreasury);
    }

    /**
        @dev Adjust gracePeriod. Only Governor can call.
        @param _gracePeriod Number of seconds to set the grace period to
    */
    function setGracePeriod(uint256 _gracePeriod) external isGovernor {
        gracePeriod = _gracePeriod;
        emit GlobalsParamSet("GRACE_PERIOD", _gracePeriod);
    }

    /**
        @dev Adjust minLoanEquity. Only Governor can call.
        @param _minLoanEquity Min percentage of Loan equity an address must have to trigger liquidations.
    */
    function setMinLoanEquity(uint256 _minLoanEquity) external isGovernor {
        _checkPercentageRange(_minLoanEquity);
        minLoanEquity = _minLoanEquity;
        emit GlobalsParamSet("MIN_LOAN_EQUITY", _minLoanEquity);
    }

    /**
        @dev Adjust drawdownGracePeriod. Only Governor can call.
        @param _drawdownGracePeriod Number of seconds to set the drawdown grace period to
    */
    function setDrawdownGracePeriod(uint256 _drawdownGracePeriod) external isGovernor {
        drawdownGracePeriod = _drawdownGracePeriod;
        emit GlobalsParamSet("DRAWDOWN_GRACE_PERIOD", _drawdownGracePeriod);
    }

    /**
        @dev Adjust the minimum Pool cover required to finalize a Pool. Only Governor can call.
        @param amt The new minimum swap out required
    */
    function setSwapOutRequired(uint256 amt) external isGovernor {
        require(amt >= uint256(10_000), "MapleGlobals:SWAP_OUT_TOO_LOW");
        swapOutRequired = amt;
        emit GlobalsParamSet("SWAP_OUT_REQUIRED", amt);
    }

    /**
        @dev Update a price feed's oracle.
        @param asset  Asset to update price for
        @param oracle New oracle to use
    */
    function setPriceOracle(address asset, address oracle) external isGovernor {
        oracleFor[asset] = oracle;
        emit OracleSet(asset, oracle);
    }

    /************************************/
    /*** Transfer Ownership Functions ***/
    /************************************/

    /**
        @dev Set a new pending Governor. This address can become governor if they accept. Only Governor can call.
        @param _pendingGovernor Address of new Governor
    */
    function setPendingGovernor(address _pendingGovernor) external isGovernor {
        require(_pendingGovernor != address(0), "MapleGlobals:ZERO_ADDRESS_GOVERNOR");
        pendingGovernor = _pendingGovernor;
        emit PendingGovernorSet(_pendingGovernor);
    }

    /**
        @dev Accept the Governor position. Only PendingGovernor can call.
    */
    function acceptGovernor() external {
        require(msg.sender == pendingGovernor, "MapleGlobals:NOT_PENDING_GOVERNOR");
        governor = pendingGovernor;
        pendingGovernor = address(0);
        emit GovernorAccepted(governor);
    }

    /************************/
    /*** Getter Functions ***/
    /************************/

    /**
        @dev Fetch price for asset from Chainlink oracles.
        @param asset Asset to fetch price
        @return Price of asset
    */
    function getLatestPrice(address asset) external view returns (uint256) {
        return uint256(IOracle(oracleFor[asset]).getLatestPrice());
    }

    /**
        @dev Check the validity of a subFactory as it relates to a superFactory.
        @param superFactory The core factory (e.g. PoolFactory, LoanFactory)
        @param subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory)
        @param factoryType  The type expected for the subFactory. References listed below.
            0 = COLLATERAL_LOCKER_FACTORY
            1 = DEBT_LOCKER_FACTORY
            2 = FUNDING_LOCKER_FACTORY
            3 = LIQUIDUITY_LOCKER_FACTORY
            4 = STAKE_LOCKER_FACTORY
    */
    function isValidSubFactory(address superFactory, address subFactory, uint8 factoryType) external view returns(bool) {
        return validSubFactories[superFactory][subFactory] && ISubFactory(subFactory).factoryType() == factoryType;
    }

    /**
        @dev Check the validity of a calculator.
        @param calc     Calculator address
        @param calcType Calculator type
    */
    function isValidCalc(address calc, uint8 calcType) external view returns(bool) {
        return validCalcs[calc] && ICalc(calc).calcType() == calcType;
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _checkPercentageRange(uint256 percentage) internal {
        require(percentage >= uint256(0) && percentage <= uint256(10_000), "MapleGlobals:PCT_BOUND_CHECK");
    }
}
