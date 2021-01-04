// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./interfaces/IPriceFeed.sol";
import "./interfaces/IERC20Details.sol";

contract MapleGlobals {
    /// @return governor is responsible for management of global Maple variables.
    address public governor;

    /// @return mapleToken is the ERC-2222 token for the Maple protocol.
    address public mapleToken;

    /// @return mapleTreasury is the Treasury which all fees pass through for conversion, prior to distribution.
    address public mapleTreasury;

    /// @return Represents the amount of time a borrower has to make a missed payment before a default can be triggered.
    uint256 public gracePeriod;

    /// @return Official balancer pool for staking.
    address public mapleBPool;

    /// @return Asset paired 50/50 with MPL in balancer pool (e.g. USDC).
    address public mapleBPoolAssetPair;

    /// @return Represents the mapleBPoolSwapOutAsset value (in wei) required when instantiating a liquidity pool.
    uint256 public stakeAmountRequired;

    /// @return Parameter for unstake delay, with relation to StakeLocker withdrawals.
    uint256 public unstakeDelay;

    /// @return Amount of time to allow borrower to drawdown on their loan after funding period ends.
    uint256 public drawdownGracePeriod;

    /// @return Establishment fee variables.
    uint256 public investorFee;
    uint256 public treasuryFee;

    // Validitying mapping of assets that borrowers can request or use as collateral.
    mapping(address => bool) public isValidBorrowToken;
    mapping(address => bool) public isValidCollateral;
    address[] public validBorrowTokenAddresses;
    string[] public validBorrowTokenSymbols;  // TODO: Account for ERC20s with bytes32 name/symbol
    address[] public validCollateralTokenAddresses;
    string[] public validCollateralTokenSymbols; // TODO: Account for ERC20s with bytes32 name/symbol

    // Mapping of asset, to the associated pricefeed.
    mapping(address => address) public tokenPriceFeed;

    mapping(address => bool) public isValidCalculator;

    // @return primary factory addresses
    address public loanVaultFactory;
    address public liquidityPoolFactory;

    /// @return Validation data structure for pool delegates (prevent invalid addresses from creating pools).
    mapping(address => bool) public validPoolDelegate;

    event CollateralTokenSet(address token, uint256 decimals, bool valid);
    event     BorrowTokenSet(address token, uint256 decimals, bool valid);

    modifier isGovernor() {
        require(msg.sender == governor, "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR");
        _;
    }

    /**
        @notice Constructor function.
        @dev Initializes the contract's state variables.
        @param _governor The administrator's address.
        @param _mapleToken The address of the ERC-2222 token for the Maple protocol.
    */
    constructor(address _governor, address _mapleToken) public {
        governor = _governor;
        mapleToken = _mapleToken;
        gracePeriod = 5 days;
        stakeAmountRequired = 100 * 10 ** 6;
        unstakeDelay = 90 days;
        drawdownGracePeriod = 1 days;
        investorFee = 50;
        treasuryFee = 50;
    }

    function getValidTokens() view public returns(
        string[] memory _validBorrowTokenSymbols,
        address[] memory _validBorrowTokenAddresses,
        string[] memory _validCollateralTokenSymbols,
        address[] memory _validCollateralTokenAddresses
    ) {
        return (
            validBorrowTokenSymbols,
            validBorrowTokenAddresses,
            validCollateralTokenSymbols,
            validCollateralTokenAddresses
        );
    }

    function setLiquidityPoolFactory(address _factory) external isGovernor {
        liquidityPoolFactory = _factory;
    }

    function setLoanVaultFactory(address _factory) external isGovernor {
        loanVaultFactory = _factory;
    }

    function setMapleBPool(address _pool) external isGovernor {
        mapleBPool = _pool;
    }

    function setPoolDelegateWhitelist(address _delegate, bool _validity) external isGovernor {
        validPoolDelegate[_delegate] = _validity;
    }

    function setMapleBPoolAssetPair(address _pair) external isGovernor {
        mapleBPoolAssetPair = _pair;
    }

    function assignPriceFeed(address _asset, address _oracle) external isGovernor {
        tokenPriceFeed[_asset] = _oracle;
    }

    function getPrice(address _asset) external view returns(uint) {
        return IPriceFeed(tokenPriceFeed[_asset]).price();
    }

    /**
        @notice Governor can add a valid token, used as collateral.
        @param _token Address of the valid token.
     */
    function setCollateralToken(address _token, bool _valid) external isGovernor {
        require(!isValidCollateral[_token], "MapleGloblas::setCollateralToken:ERR_ALREADY_ADDED");
        isValidCollateral[_token] = _valid;
        validCollateralTokenAddresses.push(_token);
        validCollateralTokenSymbols.push(IERC20Details(_token).symbol());
        emit CollateralTokenSet(_token, IERC20Details(_token).decimals(), _valid);
    }

    /**
        @notice Governor can add a valid token, used for borrowing.
        @param _token Address of the valid token.
     */
    function setBorrowToken(address _token, bool _valid) external isGovernor {
        require(!isValidBorrowToken[_token], "MapleGloblas::setBorrowToken:ERR_ALREADY_ADDED");
        isValidBorrowToken[_token] = _valid;
        validBorrowTokenAddresses.push(_token);
        validBorrowTokenSymbols.push(IERC20Details(_token).symbol());
        emit BorrowTokenSet(_token, IERC20Details(_token).decimals(), _valid);
    }

    function setCalculator(address _calculator, bool valid) public isGovernor {
        isValidCalculator[_calculator] = valid;
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
