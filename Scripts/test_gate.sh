#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

usage() {
  cat <<'EOF'
Usage: Scripts/test_gate.sh [--clean] [--skip-bun-install] [--lane all|policy|core|runtime:<shard>]

Runs the curated repo gate:
  - the same policy, root-package, platform-package, and tooling checks as
    Scripts/test_all.sh; --lane selects one CI lane of that surface (see
    Scripts/test_all.sh --help)

Pass --clean to delete every SwiftPM `.build` directory before any step runs,
trading a from-scratch rebuild for a run that cannot be tripped by stale
cross-package incremental artifacts.

Example-package coverage lives in SwiftTUI/swift-tui-examples.
EOF
}

expect_lane_value=0
for argument in "$@"; do
  if [ "$expect_lane_value" -eq 1 ]; then
    expect_lane_value=0
    continue
  fi
  case "$argument" in
  --skip-bun-install)
    ;;
  --clean)
    ;;
  --lane)
    # The value is validated by test_all.sh.
    expect_lane_value=1
    ;;
  --lane=*)
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    >&2 echo "Unknown argument: $argument"
    >&2 echo ""
    usage >&2
    exit 1
    ;;
  esac
done

command_text="sh ./Scripts/test_gate.sh"
for argument; do
  command_text="$command_text $argument"
done

export SWIFTTUI_TEST_RUNNER_NAME=test-gate
export SWIFTTUI_TEST_COMMAND_TEXT="$command_text"

exec sh "$repo_root/Scripts/test_all.sh" "$@"
