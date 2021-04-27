// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../../interfaces/IPool.sol";

contract Custodian {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function transferByCustodian(address pool, address from, address to, uint256 amt) external {
        IPool(pool).transferByCustodian(from, to, amt);
    }

    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    function try_transferByCustodian(address pool, address from, address to, uint256 amt) external returns (bool ok) {
        string memory sig = "transferByCustodian(address,address,uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, from, to, amt));
    }
}
