const { deploy } = require("@maplelabs/hardhat-scripts");

async function main() {
  const UUIDTest = await deploy("UUIDTest");
  console.log(await UUIDTest.test(0));
  console.log(await UUIDTest.test(1));

  console.log(await UUIDTest.test(2));
  console.log(await UUIDTest.test(25));
    console.log(await UUIDTest.test(26));
  console.log(await UUIDTest.test(27));

  console.log(await UUIDTest.test(33423423));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
