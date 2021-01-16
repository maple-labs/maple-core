const fs = require("fs");
const path = require("path");
const { Storage } = require("@google-cloud/storage");

async function getMapleArtifacts(network, version) {
  const storage = new Storage({
    keyFilename: "key.json",
    projectId: "maple-api-dev",
  });

  const artifactsFolder = path.join(
    __dirname,
    `../../contracts/${network}/${version}`
  );

  if (!fs.existsSync(artifactsFolder)) {
    fs.mkdirSync(artifactsFolder, { recursive: true }, (err) => {
      if (err) {
        console.log(err);
        process.kill(1);
      }
    });
  }

  const abiFolder = path.join(artifactsFolder, "abis");
  if (!fs.existsSync(abiFolder))
    fs.mkdirSync(abiFolder, (err) => {
      if (err) {
        console.log(err);
        process.kill(1);
      }
    });

  const addressFolder = path.join(artifactsFolder, "addresses");
  if (!fs.existsSync(addressFolder))
    fs.mkdirSync(addressFolder, (err) => {
      if (err) {
        console.log(err);
        process.kill(1);
      }
    });

  const bucket = storage.bucket("maple-artifacts");
  const files = await bucket.getFiles();

  files[0].forEach(async (file) => {
    if (file.name.includes(`${version}/abis`)) {
      const filePathChunks = file.name.split("/");
      const fileName = filePathChunks[filePathChunks.length - 1];
      await bucket.file(file.name).download({
        destination: abiFolder + "/" + fileName,
      });
    }

    if (file.name.includes(`${version}/addresses`)) {
      const filePathChunks = file.name.split("/");
      const fileName = filePathChunks[filePathChunks.length - 1];
      await bucket.file(file.name).download({
        destination: addressFolder + "/" + fileName,
      });
    }
  });
}

module.exports = { getMapleArtifacts };
