// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

/// @title Generates a UUID, used for Pool and Loan (debt) tokens in respective factories.
library TokenUUID {

    /**
        @dev Generates a UUID.
        @param  serial randomizes the output.
        @return UUID
    */
    function generateUUID(uint256 serial) public view returns (string memory) {

        bytes32 inBytes       = keccak256(abi.encodePacked(block.timestamp, serial));
        bytes memory outBytes = new bytes(8);

        for (uint8 i = 0; i < 7; i++) {
            uint8 digit = uint8(inBytes[i]) % 10;
            outBytes[i] = byte(48 + digit);
        }

        uint8 digit = uint8(serial) % 26;
        outBytes[7] = byte(97 + digit);

        return string(outBytes);
    }
}
