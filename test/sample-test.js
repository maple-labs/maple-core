const { expect } = require("chai");


const mpladdy= require('../../contracts/src/contracts/MapleToken.address.js')
const bpooladdy = require('../../contracts/src/contracts/BPool.address.js')

describe("Maple", function() {
   it("Check balance maple token", async function() {
   const accounts = await ethers.provider.listAccounts();
   const Mpl = await ethers.getContractFactory("MapleToken");
   const mpl =  Mpl.attach(mpladdy)
   const bal = await mpl.balanceOf(accounts[0])
   console.log("mpl bal",bal.toString())
   })
  it("set allowances to balancer pool", async function() {
      const accounts = await ethers.provider.listAccounts();
      const Mpl = await ethers.getContractFactory("MapleToken");
      const mpl =  Mpl.attach(mpladdy)
      const allowmpl = await mpl.allowance(accounts[0], bpooladdy);
      console.log("allowance mpl", allowmpl.toString() )
      await mpl.approve(bpooladdy, '5000000000000000000000') 
     const allowmpl2 = await mpl.allowance(accounts[0], bpooladdy);
      console.log("allowance2 mpl", allowmpl2.toString() )

  })

})

