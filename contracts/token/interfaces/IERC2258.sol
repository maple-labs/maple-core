// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IERC2258 is IERC20 {

    // Increase the custody limit of a custodian directly 
    function increaseCustodyAllowance(address custodian, uint256 amount) external;

    // Query individual custody limit and total custody limit across all custodians
    function custodyAllowance(address tokenHolder, address custodian) external view returns (uint256);
    function totalCustodyAllowance(address tokenHolder) external view returns (uint256);

    // Allows a custodian to exercise their right to transfer custodied tokens
    function transferByCustodian(address tokenHolder, address receiver, uint256 amount) external;

    // Custody Events
    event CustodyTransfer(address custodian, address from, address to, uint256 amount);
    event CustodyAllowanceChanged(address tokenHolder, address custodian, uint256 oldAllowance, uint256 newAllowance);
}
