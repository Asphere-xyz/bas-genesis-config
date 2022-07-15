#!/usr/bin/env bash
#set -e
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd $SCRIPT_DIR/..
yarn compile

SIMPLE_TOKEN_TEMPLATE_BYTECODE=$( cat build/contracts/SimpleToken.json | jq -r '.bytecode' | cut -c 3- )
sed -i'' -E 's/bytes constant internal SIMPLE_TOKEN_TEMPLATE_BYTECODE = hex"[0-9a-f]*";/bytes constant internal SIMPLE_TOKEN_TEMPLATE_BYTECODE = hex"'$SIMPLE_TOKEN_TEMPLATE_BYTECODE'";/g' contracts/bridge/SimpleToken.sol
sed -i'' -E 's/const SIMPLE_TOKEN_TEMPLATE_BYTECODE = "0x[0-9a-f]*";/const SIMPLE_TOKEN_TEMPLATE_BYTECODE = "0x'$SIMPLE_TOKEN_TEMPLATE_BYTECODE'";/g' ./test/bridge-utils.js

SIMPLE_TOKEN_PROXY_BYTECODE=$( cat build/contracts/SimpleTokenProxy.json | jq -r '.bytecode' | cut -c 3- )
sed -i'' -E 's/bytes constant internal SIMPLE_TOKEN_PROXY_BYTECODE = hex"[0-9a-f]*";/bytes constant internal SIMPLE_TOKEN_PROXY_BYTECODE = hex"'$SIMPLE_TOKEN_PROXY_BYTECODE'";/g' contracts/bridge/SimpleToken.sol
sed -i'' -E 's/const SIMPLE_TOKEN_PROXY_BYTECODE = "0x[0-9a-f]*";/const SIMPLE_TOKEN_PROXY_BYTECODE = "0x'$SIMPLE_TOKEN_PROXY_BYTECODE'";/g' ./test/bridge-utils.js

find ./contracts -name "*.sol-E" -delete
find ./test -name "*.js-E" -delete