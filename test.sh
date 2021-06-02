#!/usr/bin/env bash
set -e

while getopts t:r:b:v:c: flag
do
    case "${flag}" in
        t) test=${OPTARG};;
        r) runs=${OPTARG};;
        b) build=${OPTARG};;
        v) version=${OPTARG};;
        c) config=${OPTARG};;
    esac
done

runs=$([ -z "$runs" ] && echo "10" || echo "$runs")
build=$([ -z "$build" ] && echo "1" || echo "$build")
config=$([ -z "$config" ] && echo "config.json" || echo "$config")
skip_build=$([ "$build" == "0" ] && echo "1" || echo "0")
version=$([ -z "$version" ] && echo "v1" || echo "$version")

[[ $SKIP_MAINNET_CHECK || "$ETH_RPC_URL" && "$(seth chain)" == "ethlive" ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1; }

export DAPP_TEST_TIMESTAMP=1622483493
export DAPP_TEST_NUMBER=12543537
export DAPP_SOLC_VERSION=0.6.11
export DAPP_SRC="contracts"
export DAPP_LINK_TEST_LIBRARIES=0
export DAPP_STANDARD_JSON="config.json"
# export DAPP_REMAPPINGS=$(cat remappings)
# export DAPP_LIBRARIES=" contracts/libraries/loan/v1/LoanLib.sol:LoanLib:0x51A189ccD2eB5e1168DdcA7e59F7c8f39AA52232 contracts/libraries/pool/v1/PoolLib.sol:PoolLib:0x2c1C30fb8cC313Ef3cfd2E2bBf2da88AdD902C30 contracts/libraries/util/v1/Util.sol:Util:0x95f9676A34aF2675B63948dDba8F8c798741A52a"

if [ "$skip_build" = "1" ]; then export DAPP_SKIP_BUILD=1; fi

if [ -z "$test" ]; then match="[contracts/*/*/$version/test/*.t.sol]"; dapp_test_verbosity=1; else match=$test; dapp_test_verbosity=2; fi

echo LANG=C.UTF-8 dapp test --match "$match" --rpc-url "$ETH_RPC_URL" --verbosity $dapp_test_verbosity --cache "cache/dapp-cache" --fuzz-runs $runs

LANG=C.UTF-8 dapp test --match "$match" --rpc-url "$ETH_RPC_URL" --verbosity $dapp_test_verbosity --cache "cache/dapp-cache" --fuzz-runs $runs
