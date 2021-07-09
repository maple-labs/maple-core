// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.6.11;

contract GenericAccount {

    function tryCall(address someContract, bytes memory someData) external returns (bool ok, bytes memory returnData) {
        (ok, returnData) = someContract.call(someData);
    }

    function call(address someContract, bytes memory someData) external returns (bytes memory returnData) {
        bool ok;
        (ok, returnData) = someContract.call(someData);
        require(ok);
    }

}
