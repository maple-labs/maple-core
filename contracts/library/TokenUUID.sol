pragma solidity 0.7.0;

//generates UUID for various tokens in the platform

library TokenUUID {
    function hashStuff(uint256 _serial) internal view returns (bytes32) {
        uint256 _time = block.timestamp;
        return keccak256(abi.encodePacked(_time, _serial));
    }

    function mkUUID(bytes32 _inbytes) internal view returns (string memory) {
        bytes memory outbytes = new bytes(8);
        for (uint8 i = 0; i < 8; i++) {
            uint8 digit = uint8(_inbytes[i]) % 10;
            outbytes[i] = byte(48 + digit);
        }
        return string(outbytes);
    }
}
