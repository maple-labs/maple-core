// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./interfaces/IPriceFeed.sol";
import "./interfaces/IERC20Details.sol";
import "./interfaces/ISubFactory.sol";

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

    address[] public validLoanAssets;               // Array of valid loan assets (for LoanFactory).
    address[] public validCollateralAssets;         // Array of valid collateral assets (for LoanFactory).
    string[]  public validLoanAssetSymbols;         // Array of valid loan assets symbols (TODO: Consider removing)
    string[]  public validCollateralAssetSymbols;   // Array of valid collateral assets symbols (TODO: Consider removing)

    mapping(address => bool)    public isValidLoanAsset;        // Mapping of valid loan assets
    mapping(address => bool)    public isValidCollateralAsset;  // Mapping of valid collateral assets
    mapping(address => bool)    public isValidCalc;             // Mapping of valid calculator contracts
    mapping(address => bool)    public isValidPoolDelegate;     // Validation data structure for pool delegates (prevent invalid addresses from creating pools).
    mapping(address => address) public assetPriceFeed;          // Mapping of asset, to the associated oracle price feed.

    mapping(address => bool)                     public validPoolFactories;  // Mapping of valid pool factories.
    mapping(address => bool)                     public validLoanFactories;  // Mapping of valid loan factories.
    mapping(address => mapping(address => bool)) public validSubFactories;   // Mapping of valid sub factories.

    event CollateralAssetSet(address asset, uint256 decimals, bool valid);
    event       LoanAssetSet(address asset, uint256 decimals, bool valid);

    modifier isGovernor() {
        require(msg.sender == governor, "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR");
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
        swapOutRequired     = 100;
        unstakeDelay        = 90 days;
        drawdownGracePeriod = 1 days;
        investorFee         = 50;
        treasuryFee         = 50;
        BFactory            = _bFactory;
    }

    /**
        @dev Returns information on valid collateral and loan assets (for Pools and Loans).
        @return [0] = Valid loan asset symbols.
                [1] = Valid loan asset (addresses).
                [2] = Valid collateral asset symbols.
                [3] = Valid collateral asset (addresses).
    */
    function getValidTokens() view public returns(string[] memory, address[] memory, string[] memory, address[] memory) {
        return (
            validLoanAssetSymbols,
            validLoanAssets,
            validCollateralAssetSymbols,
            validCollateralAssets
        );
    }

    /**
        @dev   Update the valid pool factories mapping.
        @param poolFactory Address of loan factory.
        @param validity    The new bool value for validating poolFactory.
    */
    function setValidPoolFactory(address poolFactory, bool validity) external isGovernor {
        validPoolFactories[poolFactory] = validity;
    }

    /**
        @dev   Update the valid loan factories mapping.
        @param loanFactory Address of loan factory.
        @param validity    The new bool value for validating loanFactory.
    */
    function setValidLoanFactory(address loanFactory, bool validity) external isGovernor {
        validLoanFactories[loanFactory] = validity;
    }

    /**
        @dev    Set the validity of a subFactory as it relates to a superFactory.
        @param  superFactory The core factory (e.g. PoolFactory, LoanFactory)
        @param  subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory)
        @param  validity     The validity of subFactory within context of superFactory.
    */
    function setValidSubFactory(address superFactory, address subFactory, bool validity) external isGovernor {
        validSubFactories[superFactory][subFactory] = validity;
    }

    /**
        @dev    Get the validity of a subFactory as it relates to a superFactory.
        @param  superFactory The core factory (e.g. PoolFactory, LoanFactory)
        @param  subFactory   The sub factory used by core factory (e.g. LiquidityLockerFactory)
        @param  type         The type expected for the subFactory.
    */
    function getValidSubFactory(address superFactory, address subFactory, bytes32 type) external returns(bool) {
        return validSubFactories[superFactory][subFactory] && ISubFactory(subFactory).type() == type;
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
        assetPriceFeed[asset] = oracle;
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
        require(!isValidCollateralAsset[asset], "MapleGlobals::setCollateralAsset:ERR_ALREADY_ADDED");
        isValidCollateralAsset[asset] = valid;
        validCollateralAssets.push(asset);
        validCollateralAssetSymbols.push(IERC20Details(asset).symbol());
        emit CollateralAssetSet(asset, IERC20Details(asset).decimals(), valid);
    }

    /**
        @dev Governor can add a valid asset, used for borrowing.
        @param asset Address of the valid asset.
        @param valid Boolean
    */
    function setLoanAsset(address asset, bool valid) external isGovernor {
        require(!isValidLoanAsset[asset], "MapleGlobals::setLoanAsset:ERR_ALREADY_ADDED");
        isValidLoanAsset[asset] = valid;
        validLoanAssets.push(asset);
        validLoanAssetSymbols.push(IERC20Details(asset).symbol());
        emit LoanAssetSet(asset, IERC20Details(asset).decimals(), valid);
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
}
