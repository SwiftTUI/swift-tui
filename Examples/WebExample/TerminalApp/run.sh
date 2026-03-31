#!/usr/bin/env bash

swiftly run swift run --swift-sdk swift-6.3-RELEASE_wasm -c release -Xlinker --initial-memory=536870912 -Xlinker --max-memory=4294967296 -Xlinker -z -Xlinker "stack-size=1048576"
