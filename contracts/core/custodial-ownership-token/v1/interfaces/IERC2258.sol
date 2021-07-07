// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title ERC2258 implements the basic level functionality for a token capable of custodial ownership.
interface IERC2258 {

    /**
        @dev   Emits an event indicating a transfer was performed by a Custodian.
        @param custodian  The Custodian performing the transfer.
        @param from       The account from which balance is being decremented.
        @param to         The account receiving the token.
        @param amount     The amount transferred.
     */
    event CustodyTransfer(address custodian, address from, address to, uint256 amount);

    /**
        @dev   Emits an event indicating that the amount held by `custodian` on behalf of `account` has changed.
        @param account      The account to which the token belongs.
        @param custodian    The Custodian being entrusted.
        @param oldAllowance The old amount the account has entrusted with `custodian`.
        @param newAllowance The new amount the account has entrusted with `custodian`.
     */
    event CustodyAllowanceChanged(address account, address custodian, uint256 oldAllowance, uint256 newAllowance);

    /**
        @param  account   The account to which some token belongs.
        @param  custodian The Custodian being entrusted.
        @return The individual custody limit `account` has entrusted with `custodian`.
     */
    function custodyAllowance(address account, address custodian) external view returns (uint256);
    
    /**
        @param  account The account to which some token belongs.
        @return The total custody limit `account` has entrusted with all custodians.
     */
    function totalCustodyAllowance(address account) external view returns (uint256);

    /**
        @dev   Increase the custody limit of a custodian on behalf of the caller.
        @param custodian The Custodian being entrusted with `amount` additional token.
        @param amount    The amount of additional token being entrusted with `custodian`.
     */
    function increaseCustodyAllowance(address custodian, uint256 amount) external;

    /**
        @dev   Allows a Custodian to exercise their right to transfer custodied tokens.
        @param from       The account from which balance is being decremented.
        @param to         The account receiving the token.
        @param amount     The amount transferred.
     */
    function transferByCustodian(address from, address to, uint256 amount) external;

}
