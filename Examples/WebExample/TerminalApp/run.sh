#!/usr/bin/env bash

set -euo pipefail

swift_args=(
  --swift-sdk swift-6.3.1-RELEASE_wasm
  -c release
  -Xswiftc -Osize
  -Xswiftc -Xfrontend
  -Xswiftc -disable-llvm-merge-functions-pass
  -Xlinker --initial-memory=536870912
  -Xlinker --max-memory=4294967296
  -Xlinker -z
  -Xlinker stack-size=1048576
)

printf 'WASM_REQUIRED_FLAGS_CONFIRMED=true\n'
printf 'WASM_REQUIRED_FLAGS=%s\n' "-Xswiftc -Osize -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass"
printf 'WASM_BUILD_CONFIGURATION {"script":"run.sh","requiredFlags":"-Xswiftc -Osize -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass","command":"'
printf '%q ' swiftly run swift run "${swift_args[@]}"
printf '"}\n'
printf 'WASM_RUN_COMMAND='
printf '%q ' swiftly run swift run "${swift_args[@]}"
printf '\n'
printf 'WASM_RUN_COMMAND_ARGS_JSON='
bun -e 'console.log(JSON.stringify(process.argv.slice(1)))' -- swiftly run swift run "${swift_args[@]}"

swiftly run swift run "${swift_args[@]}"
