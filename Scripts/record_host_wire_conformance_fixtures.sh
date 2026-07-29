#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

SWIFTTUI_REGENERATE_CONFORMANCE_FIXTURES=1 \
  swiftly run swift test \
    --filter SwiftTUIAndroidHostTests.HostWireConformanceStreamRecorder
