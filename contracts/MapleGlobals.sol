pragma solidity 0.7.0;

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

    /// @return Represents the USD value a pool delegate must stake (in BPTs) when insantiating a liquidity pool.
    uint256 public stakeAmountRequired;

    /// @return Parameter for unstake delay, with relation to LiquidityPoolStakedAssetLocker withdrawals.
    uint256 public unstakeDelay;

    /// @return Amount of time to allow borrower to drawdown on their loan after funding period ends.
    uint256 public drawdownGracePeriod;

    // Validity mapping of payment intervals (in seconds).
    mapping(uint256 => bool) public validPaymentIntervalSeconds;

    // Validitying mapping of assets that borrowers can request or use as collateral.
    mapping(address => bool) public isValidBorrowToken;
    mapping(address => bool) public isValidCollateral;
    address[] public validBorrowTokenAddresses;
    address[] public validCollateralTokenAddresses;
    bytes32[] public validInterestStructures;
    //string[] public validBorrowTokenStringList;
    //string[] public validCollateralTokenStringList;

    // Mapping of bytes32 interest structure IDs to address of the corresponding interestStructureCalculators.
    mapping(bytes32 => address) public interestStructureCalculators;

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
        gracePeriod = 5 days; //432000;
        stakeAmountRequired = 25000;
        unstakeDelay = 90 days; //7776000;
        drawdownGracePeriod = 1 days; //86400;
        // solidity has time units built in minute hour day week.
        validPaymentIntervalSeconds[2592000] = true; // Monthly
        validPaymentIntervalSeconds[7776000] = true; // Quarterly
        validPaymentIntervalSeconds[15552000] = true; // Semi-annually
        validPaymentIntervalSeconds[31104000] = true; // Annually
    }

    function addCollateralToken(address _token) external isGovernor {
        isValidCollateral[_token] = true;
        validCollateralTokenAddresses.push(_token);
    }

    function addBorrowTokens(address _token) external isGovernor {
        isValidBorrowToken[_token] = true;
        validBorrowTokenAddresses.push(_token);
    }

    /**
        @notice Governor can adjust the accepted payment intervals.
        @param _paymentIntervalSeconds The payment interval.
        @param _validity The new validity of specified payment interval.
     */
    function setPaymentIntervalValidity(uint256 _paymentIntervalSeconds, bool _validity)
        public
        isGovernor
    {
        validPaymentIntervalSeconds[_paymentIntervalSeconds] = _validity;
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
