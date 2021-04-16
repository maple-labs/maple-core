// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface IPool {
    function poolDelegate() external view returns (address);

    function liquidityAsset() external view returns (address);

    function admins(address) external view returns (bool);

    function deposit(uint256) external;

    function transfer(address, uint256) external;

    function poolState() external view returns(uint256);

    function deactivate() external;

    function finalize() external;

    function claim(address, address) external returns(uint256[7] memory);

    function setLockupPeriod(uint256) external;
    
    function setStakingFee(uint256) external;

    function setAdmin(address, bool) external;

    function fundLoan(address, address, uint256) external;

    function withdraw(uint256) external;

    function withdrawFunds() external;

    function withdrawableFundsOf(address) external returns(uint256);

    function superFactory() external view returns (address);
    
    function setAllowlistStakeLocker(address, bool) external;

    function claimableFunds(address) external view returns(uint256, uint256, uint256);

    function triggerDefault(address, address) external;

    function isPoolFinalized() external view returns(bool);

    function setOpenToPublic(bool) external;

    function setAllowList(address user, bool status) external;

    function allowedLiquidityProviders(address user) external view returns(bool);

    function openToPublic() external view returns(bool);

    function intendToWithdraw() external;
}
