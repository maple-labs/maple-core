// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
import "../library/TokenUUID.sol";

/// @title Mock contract for testing a generated UUID.
contract UUIDTest {

    function test(uint256 a) public view returns (string memory _out) {
	    return TokenUUID.generateUUID(a);
    }

}
