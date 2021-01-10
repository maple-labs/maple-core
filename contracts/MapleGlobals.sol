// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./interfaces/IPriceFeed.sol";
import "./interfaces/IERC20Details.sol";

contract MapleGlobals {
    
    address public governor;             // Governor is responsible for management of global Maple variables
    address public mpl;                  // Maple Token is the ERC-2222 token for the Maple protocol
    address public mapleTreasury;        // Maple Treasury is the Treasury which all fees pass through for conversion, prior to distribution
    address public mapleBPool;           // Official balancer pool for staking (TODO: Need to handle multiple)
    address public mapleBPoolAssetPair;  // Asset paired 50/50 with MPL in balancer pool (e.g. USDC) (TODO: Need to handle multiple)
    address public loanFactory;          // Loan vault factory (TODO: Need to handle multiple)
    address public poolFactory;          // Loan vault factory (TODO: Need to handle multiple)

    uint256 public gracePeriod;          // Represents the amount of time a borrower has to make a missed payment before a default can be triggered.
    uint256 public stakeAmountRequired;  // Represents the mapleBPoolSwapOutAsset value (in wei) required when instantiating a liquidity pool.
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

    event CollateralAssetSet(address asset, uint256 decimals, bool valid);
    event       LoanAssetSet(address asset, uint256 decimals, bool valid);

    modifier isGovernor() {
        require(msg.sender == governor, "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR");
        _;
    }

    /**
        @notice Constructor function.
        @dev    Initializes the contract's state variables.
        @param  _governor The administrator's address.
        @param  _mpl The address of the ERC-2222 token for the Maple protocol.
    */
    constructor(address _governor, address _mpl) public {
        governor            = _governor;
        mpl                 = _mpl;
        gracePeriod         = 5 days;
        stakeAmountRequired = 100 * 10 ** 6;
        unstakeDelay        = 90 days;
        drawdownGracePeriod = 1 days;
        investorFee         = 50;
        treasuryFee         = 50;
    }

    /**
        @notice Returns information on valid collateral and loan assets (for Pools and Loans).
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
        @notice Set the poolFactory to a new factory.
        @param  _poolFactory The new value to assign to poolFactory.
    */
    function setPoolFactory(address _poolFactory) external isGovernor { // TODO: Change to whitelist, need to handle multiple
        poolFactory = _poolFactory;
    }

    /**
        @notice Set the loanFactory to a new factory.
        @param  _loanFactory The new value to assign to loanFactory.
    */
    function setLoanFactory(address _loanFactory) external isGovernor { // TODO: Change to whitelist, need to handle multiple
        loanFactory = _loanFactory;
    }

    /**
        @notice Set the mapleBPool to a new balancer pool.
        @param  _mapleBPool The new value to assign to mapleBPool.
    */
    function setMapleBPool(address _mapleBPool) external isGovernor {   // TODO: Handle multiple balancer pools.
        mapleBPool = _mapleBPool;
    }

    /**
        @notice Update validity of pool delegate (those able to create pools).
        @param  delegate The address to manage permissions for.
        @param  valid    The new permissions of delegate.
    */
    function setPoolDelegateWhitelist(address delegate, bool valid) external isGovernor {
        isValidPoolDelegate[delegate] = valid;
    }

    /**
        @notice Update the mapleBPoolAssetPair (initially planned to be USDC).
        @param  asset The address to manage permissions / validity for.
    */
    // TODO: Consider how this may break things.
    function setMapleBPoolAssetPair(address asset) external isGovernor {
        mapleBPoolAssetPair = asset;
    }

    /**
        @notice Update a price feed's oracle.
        @param  asset  The asset to update price for.
        @param  oracle The new oracle to use.
    */
    function assignPriceFeed(address asset, address oracle) external isGovernor {
        assetPriceFeed[asset] = oracle;
    }

    /**
        @notice Get a price feed.
        @param  asset  The asset to fetch price for.
    */
    function getPrice(address asset) external view returns(uint) {
        return IPriceFeed(assetPriceFeed[asset]).price();
    }

    /**
        @notice Set the validity of an asset for collateral.
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
        @notice Governor can add a valid asset, used for borrowing.
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
        @notice Specifiy validity of a calculator contract.
        @param  calc  The calculator.
        @param  valid The validity of calc.
    */
    function setCalc(address calc, bool valid) public isGovernor {
        isValidCalc[calc] = valid;
    }

    /**
        @notice Governor can adjust investorFee (in basis points).
        @param _fee The fee, 50 = 0.50%
    */
    function setInvestorFee(uint256 _fee) public isGovernor {
        investorFee = _fee;
    }

    /**
        @notice Governor can adjust treasuryFee (in basis points).
        @param _fee The fee, 50 = 0.50%
    */
    function setTreasuryFee(uint256 _fee) public isGovernor {
        treasuryFee = _fee;
    }

    /**
        @notice Governor can set the MapleTreasury contract.
        @param _mapleTreasury The MapleTreasury contract.
    */
    function setMapleTreasury(address _mapleTreasury) public isGovernor {
        mapleTreasury = _mapleTreasury;
    }

    /**
        @notice Governor can adjust the grace period.
        @param _gracePeriod Number of seconds to set the grace period to.
    */
    function setGracePeriod(uint256 _gracePeriod) public isGovernor {
        gracePeriod = _gracePeriod;
    }

    /**
        @notice Governor can adjust the stake amount required to create a pool.
        @param amtRequired The new minimum stake required.
    */
    function setStakeRequired(uint256 amtRequired) public isGovernor {
        stakeAmountRequired = amtRequired;
    }

    /**
        @notice Governor can specify a new governor.
        @param _newGovernor The address of new governor.
    */
    function setGovernor(address _newGovernor) public isGovernor {
        governor = _newGovernor;
    }

    /**
        @notice Governor can specify a new unstake delay value.
        @param _unstakeDelay The new unstake delay.
    */
    function setUnstakeDelay(uint256 _unstakeDelay) public isGovernor {
        unstakeDelay = _unstakeDelay;
    }
}
