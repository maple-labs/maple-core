#!/usr/bin/env bash

module=${1}
dir=$(pwd)

cd ./modules/${module}/

./build.sh

mkdir -p artifacts
mkdir -p docs
mkdir -p flat-contracts
mkdir -p standard-inputs

names=($(cat ./package.yaml | grep "    contractName:" | sed -r 's/.{18}//'))

for i in "${!names[@]}"; do
  hevm flatten --source-file contracts/${names[i]}.sol > flat-contracts/${names[i]}.sol
done

cd ${dir}

npx maple-tools build-metadata --in ./modules/${module}/out/dapp.sol.json --out ./modules/${module}/metadata.json
npx maple-tools build-artifacts --in ./modules/${module}/out/dapp.sol.json --out ./modules/${module}/artifacts
npx maple-tools build-docs --in ./modules/${module}/artifacts --out ./modules/${module}/docs --templates ./templates
npx maple-tools build-standard-json --in ./modules/${module}/flat-contracts --out ./modules/${module}/standard-inputs --config ./modules/${module}/config/prod.json
