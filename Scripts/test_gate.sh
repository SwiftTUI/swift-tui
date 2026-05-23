#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

usage() {
  cat <<'EOF'
Usage: Scripts/test_gate.sh [--clean] [--skip-bun-install]

Runs the curated repo gate:
  - the same policy, root-package, platform-package, and tooling checks as
    Scripts/test_all.sh

Pass --clean to delete every SwiftPM `.build` directory before any step runs,
trading a from-scratch rebuild for a run that cannot be tripped by stale
cross-package incremental artifacts.

Example-package coverage lives in SwiftTUI/swift-tui-examples.
EOF
}

for argument in "$@"; do
  case "$argument" in
  --skip-bun-install)
    ;;
  --clean)
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

export STUI_TEST_RUNNER_NAME=test-gate
export STUI_TEST_COMMAND_TEXT="$command_text"

exec sh "$repo_root/Scripts/test_all.sh" "$@"
