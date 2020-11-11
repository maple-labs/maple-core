pragma solidity 0.7.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidAssetLocker {

	//address to ERC20 contract for liquidAsset
	address public liquidAsset;

	IERC20 private immutable ILiquidAsset;
	// parent LP address for authorization purposes
	address public immutable ownerLP;

	constructor(address _liquidAsset, address _LPaddy) public {
		liquidAsset = _liquidAsset;
		ownerLP = _LPaddy;
		ILiquidAsset = IERC20(liquidAsset);
	}

	modifier isOwner() {
		//check if the LP is an LP as known to the factory?
		require(msg.sender == ownerLP,'ERR:LiquidAssetLocker: IS NOT OWNER POOL');
		_;
	}
	// @notice approval for spending by LP
	// @param _amt is ammmount to approve
	// @return true if successful approval
	function approve(uint _amt) isOwner external returns (bool){
		//first set allowance to 0, as a safe practice so allowance is always exactly _amt
		require(ILiquidAsset.approve(ownerLP,0),'LiquidAssetLocker: CANT SET ALLOWANCE');
		return ILiquidAsset.approve(ownerLP,_amt);
	}
}
