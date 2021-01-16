const { publish } = require("@maplelabs/hardhat-scripts");

async function main() {
  const directories = ["../contracts"];
  publish(directories);
  await new Promise((r) => setTimeout(r, 3000));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
