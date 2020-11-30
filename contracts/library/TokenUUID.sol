pragma solidity 0.7.0;

//generates UUID for various tokens in the platform

library TokenUUID {

    function mkUUID(uint256 _serial) internal view returns (string memory) {
	bytes32 _inbytes =  keccak256(abi.encodePacked(block.timestamp, _serial));
        bytes memory outbytes = new bytes(8);
        for (uint8 i = 0; i < 7; i++) {
            uint8 digit = uint8(_inbytes[i]) % 10;
            outbytes[i] = byte(48 + digit);
        }
	uint8 digit = uint8(_serial) % 26;
	outbytes[7] = byte(97 + digit);
        return string(outbytes);
    }
}
