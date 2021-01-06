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

    address[] public validLoanTokenAddresses;        // Array of valid borrow tokens (TODO: Consider removing)
    address[] public validCollateralTokenAddresses;  // Array of valid borrow tokens (TODO: Consider removing)

    string[]  public validCollateralTokenSymbols;  // Array of valid borrow token symbols (TODO: Consider removing)
    string[]  public validLoanTokenSymbols;        // Array of valid borrow token symbols (TODO: Consider removing)

    mapping(address => bool)    public isValidLoanToken;   // Mapping of valid borrow tokens
    mapping(address => bool)    public isValidCollateral;  // Mapping of valid collateral tokens
    mapping(address => bool)    public isValidCalc;        // Mapping of valid calculator contracts
    mapping(address => bool)    public validPoolDelegate;  // Validation data structure for pool delegates (prevent invalid addresses from creating pools).
    mapping(address => address) public tokenPriceFeed;     // Mapping of asset, to the associated oracle price feed.

    event CollateralTokenSet(address token, uint256 decimals, bool valid);
    event       LoanTokenSet(address token, uint256 decimals, bool valid);

    modifier isGovernor() {
        require(msg.sender == governor, "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR");
        _;
    }

    /**
        @notice Constructor function.
        @dev Initializes the contract's state variables.
        @param _governor The administrator's address.
        @param _mpl The address of the ERC-2222 token for the Maple protocol.
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

    function getValidTokens() view public returns(
        string[]  memory _validLoanTokenSymbols,
        address[] memory _validLoanTokenAddresses,
        string[]  memory _validCollateralTokenSymbols,
        address[] memory _validCollateralTokenAddresses
    ) {
        return (
            validLoanTokenSymbols,
            validLoanTokenAddresses,
            validCollateralTokenSymbols,
            validCollateralTokenAddresses
        );
    }

    function setPoolFactory(address _poolFactory) external isGovernor { // TODO: Change to whitelist, need to handle multiple
        poolFactory = _poolFactory;
    }

    function setLoanFactory(address _loanFactory) external isGovernor { // TODO: Change to whitelist, need to handle multiple
        loanFactory = _loanFactory;
    }

    function setMapleBPool(address _mapleBPool) external isGovernor {   // TODO: Change to whitelist, need to handle multiple
        mapleBPool = _mapleBPool;
    }

    function setPoolDelegateWhitelist(address delegate, bool valid) external isGovernor {
        validPoolDelegate[delegate] = valid;
    }

    function setMapleBPoolAssetPair(address _pair) external isGovernor {
        mapleBPoolAssetPair = _pair;
    }

    function assignPriceFeed(address asset, address oracle) external isGovernor {
        tokenPriceFeed[asset] = oracle;
    }

    function getPrice(address asset) external view returns(uint) {
        return IPriceFeed(tokenPriceFeed[asset]).price();
    }

    /**
        @notice Governor can add a valid token, used as collateral.
        @param token Address of the valid token.
        @param valid Boolean
     */
    function setCollateralToken(address token, bool valid) external isGovernor {
        require(!isValidCollateral[token], "MapleGloblas::setCollateralToken:ERR_ALREADY_ADDED");
        isValidCollateral[token] = valid;
        validCollateralTokenAddresses.push(token);
        validCollateralTokenSymbols.push(IERC20Details(token).symbol());
        emit CollateralTokenSet(token, IERC20Details(token).decimals(), valid);
    }

    /**
        @notice Governor can add a valid token, used for borrowing.
        @param token Address of the valid token.
        @param valid Boolean
     */
    function setLoanToken(address token, bool valid) external isGovernor {
        require(!isValidLoanToken[token], "MapleGloblas::setLoanToken:ERR_ALREADY_ADDED");
        isValidLoanToken[token] = valid;
        validLoanTokenAddresses.push(token);
        validLoanTokenSymbols.push(IERC20Details(token).symbol());
        emit LoanTokenSet(token, IERC20Details(token).decimals(), valid);
    }

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
        @notice Governor can adjust the stake amount required to create a liquidity pool.
        @param _newAmount The new minimum stake required.
     */
    function setStakeRequired(uint256 _newAmount) public isGovernor {
        stakeAmountRequired = _newAmount;
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
