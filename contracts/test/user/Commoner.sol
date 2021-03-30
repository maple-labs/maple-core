// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

contract Commoner {

    function try_setLiquidityCap(address pool, uint256 liquidityCap) external returns(bool ok) {
        string memory sig = "setLiquidityCap(uint256)";
        (ok,) = address(pool).call(abi.encodeWithSignature(sig, liquidityCap));
    }

    function try_triggerDefault(address loan) external returns (bool ok) {
        string memory sig = "triggerDefault()";
        (ok,) = loan.call(abi.encodeWithSignature(sig));
    }

    function try_setProtocolPause(address globals, bool pause) external returns (bool ok) {
        string memory sig = "setProtocolPause(bool)";
        (ok,) = globals.call(abi.encodeWithSignature(sig, pause));
    }

    function try_pause(address target) external returns (bool ok) {
        string memory sig = "pause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }

    function try_unpause(address target) external returns (bool ok) {
        string memory sig = "unpause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }
}
