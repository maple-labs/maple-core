const { expect, assert } = require("chai");

describe("Borrower Journey", function () {

  it("A - Fetch the list of borrowTokens / collateralTokens", async function () {

    const MapleGlobalsAddress = require("../../contracts/localhost/addresses/MapleGlobals.address");
    const MapleGlobalsABI = require("../../contracts/localhost/abis/MapleGlobals.abi");

    let MapleGlobals;

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    const List = await MapleGlobals.getValidTokens();

    // These two arrays are related, in order.
    console.log(List["_validBorrowTokenSymbols"]);
    console.log(List["_validBorrowTokenAddresses"]);
    
    // These two arrays are related, in order.
    console.log(List["_validCollateralTokenSymbols"]);
    console.log(List["_validCollateralTokenAddresses"]);

  });

});
