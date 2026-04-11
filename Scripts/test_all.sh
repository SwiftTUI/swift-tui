#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

skip_bun_install=0
host_os=$(uname -s)
is_linux=0
failures=""

if [ "$host_os" = "Linux" ]; then
  is_linux=1
  export DISABLE_EXPLICIT_PLATFORMS=1
fi

usage() {
  cat <<'EOF'
Usage: Scripts/test_all.sh [--skip-bun-install]

Runs the full checked-in repo verification surface:
  - checked-in policy hooks
  - root SwiftPM tests
  - Runners/TerminalUICLI tests
  - Runners/TerminalUIWASI tests
  - GUI/SwiftUITUIGUI tests
  - GUI/WebTUIGUI Bun tests
  - Examples/gallery tests
  - Examples/WebExample Bun tests

The script also checks required environment dependencies up front:
  - Swift 6.3.x via `swiftly` when available, otherwise `swift`
  - Bun availability
  - Bun workspace dependencies via `bun install --frozen-lockfile` at the repo root

On Linux, the script also:
  - exports `DISABLE_EXPLICIT_PLATFORMS=1` for repo package resolution
  - skips `GUI/SwiftUITUIGUI` tests because the SwiftUI host package is Apple-only

Pass --skip-bun-install to reuse the existing Bun install state.
EOF
}

add_failure() {
  title=$1
  if [ -z "$failures" ]; then
    failures=$title
  else
    failures=$failures'
'$title
  fi
}

for argument in "$@"; do
  case "$argument" in
    --skip-bun-install)
      skip_bun_install=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      >&2 echo "Unknown argument: $argument"
      >&2 echo ""
      usage
      exit 1
      ;;
  esac
done

SWIFT_LAUNCHER=""

detect_swift_command() {
  if command -v swiftly >/dev/null 2>&1; then
    SWIFT_LAUNCHER=swiftly
    return 0
  fi

  if command -v swift >/dev/null 2>&1; then
    SWIFT_LAUNCHER=swift
    return 0
  fi

  >&2 echo "Missing required command: swiftly or swift"
  exit 1
}

run_swift() {
  if [ "$SWIFT_LAUNCHER" = "swiftly" ]; then
    swiftly run swift "$@"
  else
    swift "$@"
  fi
}

require_command() {
  name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    >&2 echo "Missing required command: $name"
    exit 1
  fi
}

run_step() {
  title=$1
  workdir=$2
  shift 2

  echo ""
  echo "==> $title"

  if (
    cd "$workdir" &&
    "$@"
  ); then
    echo "PASS: $title"
  else
    >&2 echo "FAIL: $title"
    add_failure "$title"
  fi
}

run_function_step() {
  title=$1
  shift

  echo ""
  echo "==> $title"

  if "$@"; then
    echo "PASS: $title"
  else
    >&2 echo "FAIL: $title"
    add_failure "$title"
  fi
}

skip_step() {
  title=$1
  reason=$2

  echo ""
  echo "==> $title"
  echo "SKIP: $title ($reason)"
}

check_swift_environment() {
  version_output=$(run_swift --version 2>&1)
  echo "$version_output"

  case "$version_output" in
    *"Swift version 6.3"*|*"Apple Swift version 6.3"*)
      return 0
      ;;
    *)
      >&2 echo ""
      >&2 echo "Expected Swift 6.3.x for this repository."
      >&2 echo "Use 'swiftly run swift ...' directly, or make sure 'swift' resolves to the swiftly-managed toolchain."
      return 1
      ;;
  esac
}

check_bun_environment() {
  bun --version
}

detect_swift_command
require_command bun

if [ "$is_linux" -eq 1 ]; then
  echo "Linux host detected; exporting DISABLE_EXPLICIT_PLATFORMS=1 and skipping Apple-only SwiftUI host tests."
fi

run_function_step "Check Swift toolchain" check_swift_environment
run_function_step "Check Bun availability" check_bun_environment

if [ -f "$repo_root/package.json" ] && [ -f "$repo_root/bun.lock" ] && [ "$skip_bun_install" -eq 0 ]; then
  run_step \
    "Install Bun workspace dependencies" \
    "$repo_root" \
    bun install --frozen-lockfile
fi

run_step \
  "Check public-surface policies" \
  "$repo_root" \
  ./Scripts/check_public_surface_policies.sh

run_step \
  "Check concurrency-safety policies" \
  "$repo_root" \
  ./Scripts/check_concurrency_safety_policies.sh

run_function_step \
  "Run root SwiftPM tests" \
  run_swift test

run_function_step \
  "Run Runners/TerminalUICLI tests" \
  run_swift test --package-path Runners/TerminalUICLI

run_function_step \
  "Run Runners/TerminalUIWASI tests" \
  run_swift test --package-path Runners/TerminalUIWASI

if [ "$is_linux" -eq 1 ]; then
  skip_step \
    "Run GUI/SwiftUITUIGUI tests" \
    "SwiftUI host package is only available on Apple platforms"
else
  run_function_step \
    "Run GUI/SwiftUITUIGUI tests" \
    run_swift test --package-path GUI/SwiftUITUIGUI
fi

run_step \
  "Run GUI/WebTUIGUI Bun tests" \
  "$repo_root/GUI/WebTUIGUI" \
  bun test

run_function_step \
  "Run Examples/gallery tests" \
  run_swift test --package-path Examples/gallery

run_step \
  "Run Examples/WebExample Bun tests" \
  "$repo_root/Examples/WebExample" \
  bun test

echo ""

if [ -z "$failures" ]; then
  echo "All repo tests succeeded."
  exit 0
fi

>&2 echo "Repo test failures:"
OLD_IFS=$IFS
IFS='
'
for failure in $failures; do
  >&2 echo "  - $failure"
done
IFS=$OLD_IFS

exit 1