pragma solidity 0.7.0;

interface IGlobals {
    function governor() external view returns (address);

    function mapleToken() external view returns (address);

    function mapleTreasury() external view returns (address);

    function establishmentFeeBasisPoints() external view returns (uint256);

    function treasuryFeeBasisPoints() external view returns (uint256);

    function gracePeriod() external view returns (uint256);

    function drawdownGracePeriod() external view returns (uint256);

    function stakeAmountRequired() external view returns (uint256);

    function isValidBorrowToken(address) external view returns (bool);

    function isValidCollateral(address) external view returns (bool);

    function validBorrowTokenAddresses() external view returns (address[] memory);

    function validCollateralTokenAddresses() external view returns (address[] memory);

    function interestStructureCalculators(bytes32) external view returns (address);

    function validInterestStructures() external view returns (bytes32[] memory);

    function unstakeDelay() external view returns (uint256);
}