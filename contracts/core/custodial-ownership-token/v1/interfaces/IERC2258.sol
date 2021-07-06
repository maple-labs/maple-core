// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

/// @title ERC2258 implements the basic level functionality for a token capable of custodial ownership.
interface IERC2258 {

    // Custody Events
    event CustodyTransfer(address custodian, address from, address to, uint256 amount);
    event CustodyAllowanceChanged(address account, address custodian, uint256 oldAllowance, uint256 newAllowance);

    // Increase the custody limit of a custodian either directly or via signed authorization
    function increaseCustodyAllowance(address custodian, uint256 amount) external;

    // Query individual custody limit and total custody limit across all custodians
    function custodyAllowance(address account, address custodian) external view returns (uint256);
    function totalCustodyAllowance(address account) external view returns (uint256);

    /**
        @dev Allows a custodian to exercise their right to transfer custodied tokens.
     */
    function transferByCustodian(address from, address to, uint256 amount) external;

}
