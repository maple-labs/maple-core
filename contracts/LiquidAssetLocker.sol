pragma solidity 0.7.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILoanVault {
    function fundLoan(uint256 _amount) external;
}

contract LiquidAssetLocker {
    //address to ERC20 contract for liquidAsset
    address public liquidAsset;

    IERC20 private immutable ILiquidAsset;

    // parent LP address for authorization purposes
    address public immutable ownerLP;

    constructor(address _liquidAsset, address _LPaddy) public {
        liquidAsset = _liquidAsset;
        //should maybe check if this address is indeed an LP fro the factory
        ownerLP = _LPaddy;
        ILiquidAsset = IERC20(liquidAsset);
    }

    modifier isOwner() {
        //check if the LP is an LP as known to the factory?
        require(msg.sender == ownerLP, "ERR:LiquidAssetLocker: IS NOT OWNER POOL");
        _;
    }

    // @notice transfer funds
    // @param _amt is ammount to transfer
    // @param _to address to send to
    // @return true if transfer succeeds
    function transfer(address _to, uint256 _amt) external isOwner returns (bool) {
        require(_to != address(0), "ERR:LiquidAssetLocker: NO SEND TO 0 ADDRESS");
        return ILiquidAsset.transfer(_to, _amt);
    }

    // @notice approve and call fundloan in loanvault
    //check if it is actually a loan vault
    function fundLoan(address _loanVault, uint256 _amt) isOwner external {
        ILiquidAsset.approve(_loanVault, _amt);
	ILoanVault(_loanVault).fundLoan(_amt);
    }
}
