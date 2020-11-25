pragma solidity 0.7.0;

contract MapleGlobals {

    /// @return governor is responsible for management of global Maple variables.
    address public governor;

    /// @return mapleToken is the ERC-2222 token for the Maple protocol.
    address public mapleToken;

    /// @return mapleTreasury is the Treasury which all fees pass through for conversion, prior to distribution.
    address public mapleTreasury;

    /// @return Represents the fees, in basis points, distributed to the lender when a borrower's loan is funded.
    uint public establishmentFeeBasisPoints;

    /// @return Represents the fees, in basis points, distributed to the Mapletoken when a borrower's loan is funded.
    uint public treasuryFeeBasisPoints;

    /// @return Represents the amount of time a borrower has to make a missed payment before a default can be triggered.
    uint public gracePeriod;

    /// @return Represents the USD value a pool delegate must stake (in BPTs) when insantiating a liquidity pool.
    uint public stakeAmountRequired;

    /// @return Parameter for unstake delay, with relation to LiquidityPoolStakedAssetLocker withdrawals.
    uint public unstakeDelay;

    // Validity mapping of payment intervals (in seconds).
    mapping(uint => bool) public validPaymentIntervalSeconds;

    // Mapping of bytes32 interest structure IDs to address of the corresponding repaymentCalculator.
    mapping(bytes32 => address) public interestStructureCalculators;

    modifier isGovernor() {
        require(msg.sender == governor, "msg.sender is not Governor");
        _;
    }

    /**
        @notice Constructor function.
        @dev Initializes the contract's state variables.
        @param _governor The administrator's address.
        @param _mapleToken The address of the ERC-2222 token for the Maple protocol.
    */
    constructor(
        address _governor,
        address _mapleToken
    ) { 
        governor = _governor;
        mapleToken = _mapleToken;
        establishmentFeeBasisPoints = 200;
        treasuryFeeBasisPoints = 20;
        gracePeriod = 432000;
        stakeAmountRequired = 25000;
        unstakeDelay = 7776000;

        validPaymentIntervalSeconds[2592000] = true;    // Monthly
        validPaymentIntervalSeconds[7776000] = true;    // Quarterly
        validPaymentIntervalSeconds[15552000] = true;   // Semi-annually
        validPaymentIntervalSeconds[31104000] = true;   // Annually
    }

    /**
        @notice Governor can adjust the accepted payment intervals.
        @param _paymentIntervalSeconds The payment interval.
        @param _validity The new validity of specified payment interval.
     */
    function setPaymentIntervalValidity(uint _paymentIntervalSeconds, bool _validity) isGovernor public {
        validPaymentIntervalSeconds[_paymentIntervalSeconds] = _validity;
    }

    /**
        @notice Governor can adjust the grace period.
        @param _interestStructure Name of the interest structure (e.g. "BULLET")
        @param _calculator Address of the corresponding calculator for repayments, etc.
     */
    function setInterestStructureCalculator(bytes32 _interestStructure, address _calculator) isGovernor public {
        interestStructureCalculators[_interestStructure] = _calculator;
    }

    /**
        @notice Governor can adjust the establishment fee.
        @param _establishmentFeeBasisPoints The fee, 50 = 0.50%
     */
    function setEstablishmentFee(uint _establishmentFeeBasisPoints) isGovernor public {
        establishmentFeeBasisPoints = _establishmentFeeBasisPoints;
    }

    /**
        @notice Governor can set the MapleTreasury contract.
        @param _mapleTreasury The MapleTreasury contract.
     */
    function setMapleTreasury(address _mapleTreasury) isGovernor public {
        mapleTreasury = _mapleTreasury;
    }

    /**
        @notice Governor can adjust the treasury fee.
        @param _treasuryFeeBasisPoints The fee, 50 = 0.50%
     */
    function setTreasurySplit(uint _treasuryFeeBasisPoints) isGovernor public {
        treasuryFeeBasisPoints = _treasuryFeeBasisPoints;
    }

    /**
        @notice Governor can adjust the grace period.
        @param _gracePeriod Number of seconds to set the grace period to.
     */
    function setGracePeriod(uint _gracePeriod) isGovernor public {
        gracePeriod = _gracePeriod;
    }

    /**
        @notice Governor can adjust the stake amount required to create a liquidity pool.
        @param _newAmount The new minimum stake required.
     */
    function setStakeRequired(uint _newAmount) isGovernor public {
        stakeAmountRequired = _newAmount;
    }

    /**
        @notice Governor can specify a new governor.
        @param _newGovernor The address of new governor.
     */
    function setGovernor(address _newGovernor) isGovernor public {
        governor = _newGovernor;
    }

    /**
        @notice Governor can specify a new unstake delay value.
        @param _unstakeDelay The new unstake delay.
     */
    function setUnstakeDelay(uint _unstakeDelay) isGovernor public {
        unstakeDelay = _unstakeDelay;
    }


}
