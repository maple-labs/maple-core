pragma solidity 0.7.0;

contract MapleGlobals {

    /// @return governor is responsible for management of global Maple variables.
    address public governor;

    /// @return mapleToken is the ERC-2222 token for the Maple protocol.
    address public mapleToken;

    /// @return Represents the fees, in basis points, distributed to the lender when a borrower's loan is funded.
    uint public establishmentFeeBasisPoints;

    /// @return Represents the fees, in basis points, distributed to the Mapletoken when a borrower's loan is funded.
    uint public treasuryFeeBasisPoints;

    /// @return Represents the amount of time a borrower has to make a missed payment before a default can be triggered.
    uint public gracePeriod;

    modifier isGovernor() {
        require(msg.sender == governor, "msg.sender is not Governor");
        _;
    }

    /**
        @notice Constructor function.
        @dev Initializes the contract's state variables.
        @param _governor The administrator's address.
        @param _mapleTokenAddress The address of the ERC-2222 token for the Maple protocol.
    */
    constructor(
        address _governor,
        address _mapleTokenAddress
    ) { 
        governor = _governor;
        mapleToken = _mapleTokenAddress; 
        establishmentFeeBasisPoints = 200;
        treasuryFeeBasisPoints = 20;
        gracePeriod = 432000;
    }

    /**
        @notice Governor can adjust the establishment fee.
        @param _establishmentFeeBasisPoints The fee, 50 = 0.50%
     */
    function setEstablishmentFee(uint _establishmentFeeBasisPoints) isGovernor public {
        establishmentFeeBasisPoints = _establishmentFeeBasisPoints;
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
        @notice Governor can specify a new governor.
        @param _newGovernor The address of new governor.
     */
    function setGovernor(address _newGovernor) isGovernor public {
        governor = _newGovernor;
    }

}
