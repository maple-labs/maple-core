// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//import "./interface/ILoanVault.sol";

contract LoanTokenLocker {
    // parent LP address for authorization purposes
    address public immutable ownerLP;
    address public immutable loanToken;

    constructor(address _loanToken, address _LPaddy) {
        ownerLP = _LPaddy;
        loanToken = _loanToken;
    }

    modifier isOwner() {
        //check if the LP is an LP as known to the factory?
        require(msg.sender == ownerLP, "ERR:LoanTokenLocker: IS NOT OWNER POOL");
        _;
    }
}
