all       :; DAPP_SRC=contracts DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.11 build
clean     :; dapp clean
unit-test :; ./test.sh
fuzz-test :; ./test-fuzz.sh
ci-test   :; ./test-ci.sh
