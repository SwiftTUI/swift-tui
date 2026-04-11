#!/usr/bin/env bash

set -euo pipefail

swift_args=(
  --swift-sdk swift-6.3-RELEASE_wasm
  -c release
  -Xswiftc -Osize
  -Xswiftc -Xfrontend
  -Xswiftc -disable-llvm-merge-functions-pass
  -Xlinker --initial-memory=536870912
  -Xlinker --max-memory=4294967296
  -Xlinker -z
  -Xlinker stack-size=1048576
)

printf 'WASM_BUILD_CONFIGURATION {"script":"run.sh","requiredFlags":"-Xswiftc -Osize -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass","command":"'
printf '%q ' swiftly run swift run "${swift_args[@]}"
printf '"}\n'

swiftly run swift run "${swift_args[@]}"
