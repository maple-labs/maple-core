pragma solidity 0.7.0;

interface IERC20Details {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint);
}
