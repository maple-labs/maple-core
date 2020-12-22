// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;
import "../lib/openzeppelin-contracts/src/token/ERC20/IERC20.sol";

contract LoanTokenLocker {

    /// @notice The LoanToken this vault is holding.
    address public immutable loanToken;

    /// @notice The owner of this Locker (a liquidity pool).
    address public immutable owner;

    constructor(address _loanToken, address _owner) {
        loanToken = _loanToken;
        owner = _owner;
    }

    modifier isOwner() {
        require(msg.sender == owner, "LoanTokenLocker:ERR_MSG_SENDER_NOT_OWNER");
        _;
    }
}
