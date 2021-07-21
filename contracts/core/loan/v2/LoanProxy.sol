// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { TransparentUpgradeableProxy } from "../../../../lib/openzeppelin-contracts/contracts/proxy/TransparentUpgradeableProxy.sol";

/**
 * @title LoanProxy
 */
contract LoanProxy is TransparentUpgradeableProxy {
    /**
        @notice Constructor
        @param _logic representing the address of the new implementation to be set
        @param admin_ Admin of the proxy.
        @param _data  Intitalize function data to call.
    */
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    )
        public
        TransparentUpgradeableProxy(_logic, admin_, _data)
    {
    }

}
