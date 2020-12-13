// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;
pragma experimental ABIEncoderV2;

import "./interface/IPriceFeed.sol";
import "./interface/IERC20Details.sol";

contract MapleGlobals {
    /// @return governor is responsible for management of global Maple variables.
    address public governor;

    /// @return mapleToken is the ERC-2222 token for the Maple protocol.
    address public mapleToken;

    /// @return mapleTreasury is the Treasury which all fees pass through for conversion, prior to distribution.
    address public mapleTreasury;

    /// @return Represents the fees, in basis points, distributed to the lender when a borrower's loan is funded.
    uint256 public establishmentFeeBasisPoints;

    /// @return Represents the fees, in basis points, distributed to the Mapletoken when a borrower's loan is funded.
    uint256 public treasuryFeeBasisPoints;

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

    // Validitying mapping of assets that borrowers can request or use as collateral.
    mapping(address => bool) public isValidBorrowToken;
    mapping(address => bool) public isValidCollateral;
    address[] public validBorrowTokenAddresses;
    string[] public validBorrowTokenSymbols;
    address[] public validCollateralTokenAddresses;
    string[] public validCollateralTokenSymbols;

    // Mapping of asset, to the associated pricefeed.
    mapping(address => address) public tokenPriceFeed;

    // Mapping of bytes32 interest structure IDs to address of the corresponding interestStructureCalculators.
    mapping(bytes32 => address) public interestStructureCalculators;
    bytes32[] public validInterestStructures;

    // @return primary factory addresses
    address public loanVaultFactory;
    address public liquidityPoolFactory;

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
    constructor(address _governor, address _mapleToken) {
        governor = _governor;
        mapleToken = _mapleToken;
        establishmentFeeBasisPoints = 200;
        treasuryFeeBasisPoints = 20;
        gracePeriod = 5 days;
        stakeAmountRequired = 0;
        unstakeDelay = 90 days;
        drawdownGracePeriod = 1 days;
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
    function addCollateralToken(address _token) external isGovernor {
        require(!isValidCollateral[_token], "MapleGloblas::addCollateralToken:ERR_ALREADY_ADDED");
        isValidCollateral[_token] = true;
        validCollateralTokenAddresses.push(_token);
        validCollateralTokenSymbols.push(IERC20Details(_token).symbol());
    }

    /**
        @notice Governor can add a valid token, used for borrowing.
        @param _token Address of the valid token.
     */
    function addBorrowToken(address _token) external isGovernor {
        require(!isValidBorrowToken[_token], "MapleGloblas::addBorrowTokens:ERR_ALREADY_ADDED");
        isValidBorrowToken[_token] = true;
        validBorrowTokenAddresses.push(_token);
        validBorrowTokenSymbols.push(IERC20Details(_token).symbol());
    }

    /**
        @notice Governor can adjust the accepted payment intervals.
        @param _type The bytes32 name identifying the interest structure (e.g. "BULLET")
        @param _calculator Address of the calculator.
     */
    function addValidInterestStructure(bytes32 _type, address _calculator) external isGovernor {
        require(
            _calculator != address(0),
            "MapleGloblas::addValidInterestStructure:ERR_NULL_ADDRESS_SUPPLIED_FOR_CALCULATOR"
        );
        require(
            interestStructureCalculators[_type] == address(0),
            "MapleGloblas::addValidInterestStructure:ERR_ALREADY_ADDED"
        );
        interestStructureCalculators[_type] = _calculator;
        validInterestStructures.push(_type);
    }

    /**
        @notice Governor can adjust the grace period.
        @param _interestStructure Name of the interest structure (e.g. "BULLET")
        @param _calculator Address of the corresponding calculator for repayments, etc.
     */
    function setInterestStructureCalculator(bytes32 _interestStructure, address _calculator)
        public
        isGovernor
    {
        interestStructureCalculators[_interestStructure] = _calculator;
        validInterestStructures.push(_interestStructure);
    }

    /**
        @notice Governor can adjust the establishment fee.
        @param _establishmentFeeBasisPoints The fee, 50 = 0.50%
     */
    function setEstablishmentFee(uint256 _establishmentFeeBasisPoints) public isGovernor {
        establishmentFeeBasisPoints = _establishmentFeeBasisPoints;
    }

    /**
        @notice Governor can set the MapleTreasury contract.
        @param _mapleTreasury The MapleTreasury contract.
     */
    function setMapleTreasury(address _mapleTreasury) public isGovernor {
        mapleTreasury = _mapleTreasury;
    }

    /**
        @notice Governor can adjust the treasury fee.
        @param _treasuryFeeBasisPoints The fee, 50 = 0.50%
     */
    function setTreasurySplit(uint256 _treasuryFeeBasisPoints) public isGovernor {
        treasuryFeeBasisPoints = _treasuryFeeBasisPoints;
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
