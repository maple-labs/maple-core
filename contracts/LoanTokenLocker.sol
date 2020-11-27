pragma solidity 0.7.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//import "./interface/ILoanVault.sol";

contract LoanTokenLocker {
    // parent LP address for authorization purposes
    address public immutable ownerLP;

    constructor(address _LPaddy) public {
        ownerLP = _LPaddy;
    }

    modifier isOwner() {
        //check if the LP is an LP as known to the factory?
        require(msg.sender == ownerLP, "ERR:LiquidAssetLocker: IS NOT OWNER POOL");
        _;
    }
}
