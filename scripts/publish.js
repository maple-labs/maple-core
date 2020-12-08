const { publish } = require("@maplelabs/hardhat-scripts");

async function main() {
  const directories = ["../maple-webapp/src/contracts"];
  publish(directories);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
