#!/usr/bin/env bash
set -e

while getopts c: flag
do
    case "${flag}" in
        c) config=${OPTARG};;
    esac
done

config=$([ -z "$config" ] && echo "config.json" || echo "$config")

export DAPP_TEST_TIMESTAMP=1622483493
export DAPP_TEST_NUMBER=12543537
export DAPP_SOLC_VERSION=0.6.11
export DAPP_SRC="contracts"
export DAPP_BUILD_OPTIMIZE=0
export DAPP_BUILD_OPTIMIZE_RUNS=200
export DAPP_LINK_TEST_LIBRARIES=0
export DAPP_STANDARD_JSON=$config
# export DAPP_REMAPPINGS=$(cat remappings)
# export DAPP_LIBRARIES=" contracts/libraries/loan/v1/LoanLib.sol:LoanLib:0x51A189ccD2eB5e1168DdcA7e59F7c8f39AA52232 contracts/libraries/pool/v1/PoolLib.sol:PoolLib:0x2c1C30fb8cC313Ef3cfd2E2bBf2da88AdD902C30 contracts/libraries/util/v1/Util.sol:Util:0x95f9676A34aF2675B63948dDba8F8c798741A52a"

dapp --use solc:0.6.11 build
