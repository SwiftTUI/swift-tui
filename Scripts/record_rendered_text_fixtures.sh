#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

export STUI_RECORD_RENDERED_TEXT_FIXTURES=1
export STUI_RENDERED_TEXT_FIXTURE_RECORDING_SCRIPT=1

swiftly run swift test --filter SwiftTUITests.NonAggregatingViewFixtureTests
./Scripts/check_rendered_text_fixture_matrix.sh
