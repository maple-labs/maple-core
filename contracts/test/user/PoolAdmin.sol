// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../../interfaces/IPool.sol";

contract PoolAdmin {
    function try_claim(address pool, address loan, address dlFactory) external returns (bool ok) {
        string memory sig = "claim(address,address)";
        (ok,) = pool.call(abi.encodeWithSignature(sig, loan, dlFactory));
    }

    function claim(address pool, address loan, address dlFactory) external { IPool(pool).claim(loan, dlFactory); }
}
