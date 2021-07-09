// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { IPool } from "../../core/pool/v1/interfaces/IPool.sol";

contract Custodian {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function transferByCustodian(address erc2258, address from, address to, uint256 amt) external {
        IPool(erc2258).transferByCustodian(from, to, amt);
    }

    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    function try_transferByCustodian(address erc2258, address from, address to, uint256 amt) external returns (bool ok) {
        string memory sig = "transferByCustodian(address,address,uint256)";
        (ok,) = address(erc2258).call(abi.encodeWithSignature(sig, from, to, amt));
    }
}
