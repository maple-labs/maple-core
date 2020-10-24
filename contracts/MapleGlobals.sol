pragma solidity 0.7.3;

contract MapleGlobals {

    /// @return Governor is responsible for management of global Maple variables.
    address public Governor;

    /// @return MapleToken is the ERC-2222 token for the Maple protocol.
    address public MapleToken;

    /// @return Represents the fees, in basis points, distributed to the lender when a borrower's loan is funded.
    uint public EstablishmentFeeBasisPoints;

    /// @return Represents the fees, in basis points, distributed to the Mapletoken when a borrower's loan is funded.
    uint public TreasurySplitBasisPoints;

    /// @return Represents the 
    uint public PoolSplitBasisPoints;
    uint public UnstakeDelay;
    uint public GracePeriod;

    modifier isGovernor() {
        require(msg.sender == Governor, "msg.sender is not Governor");
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
    ) public { 
        Governor = _governor;
        MapleToken = _mapleTokenAddress; 
        EstablishmentFeeBasisPoints = 20;
        TreasurySplitBasisPoints = 20;
        PoolSplitBasisPoints = 20;
        UnstakeDelay = 1209600;
        GracePeriod = 604800;
    }

    function setEstablishmentFee(uint _establishmentFee) isGovernor public {
        EstablishmentFeeBasisPoints = _establishmentFee; // Upper limit?
    }

    function setTreasurySplit(uint _treasurySplit) isGovernor public {
        TreasurySplitBasisPoints = _treasurySplit;
    }

    function setPoolSplit(uint _poolSplit) isGovernor public {
        PoolSplitBasisPoints = _poolSplit;
    }

    function setUnstakeDelay(uint _unstakeDelay) isGovernor public {
        UnstakeDelay = _unstakeDelay;
    }

    function setGracePeriod(uint _gracePeriod) isGovernor public {
        TreasurySplitBasisPoints = _gracePeriod;
    }

}
