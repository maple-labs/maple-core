const { deploy } = require("@maplelabs/hardhat-scripts");

async function main() {
  const UUIDTest = await deploy("UUIDTest");
  console.log(await UUIDTest.test(3));
    console.log(await UUIDTest.test(1));

      console.log(await UUIDTest.test(5));

        console.log(await UUIDTest.test(33423423));

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
