// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;
import "../library/TokenUUID.sol";

//generates UUID for various tokens in the platform

contract UUIDTest {
    
    function test(uint256 _serial) public view returns (string memory _out){
	return TokenUUID.mkUUID(_serial);
    }
}
