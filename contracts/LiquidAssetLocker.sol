pragma solidity 0.7.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidAssetLocker {

	//address to ERC20 contract for liquidAsset
	address public liquidAsset;

	// parent LP address for authorization purposes
	address public immutable ownerLP;

	constructor(address _liquidAsset, address _LPaddy) public {
		liquidAsset = _liquidAsset;
		ownerLP = _LPaddy;
	}

	modifier isOwner(address _addy) {
		require(_addy == ownerLP);
		_;
	}
}
