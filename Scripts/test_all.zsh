#!/usr/bin/env zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

skip_bun_install=0

usage() {
  cat <<'EOF'
Usage: Scripts/test_all.zsh [--skip-bun-install]

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

Pass --skip-bun-install to reuse the existing Bun install state.
EOF
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
      print -u2 -- "Unknown argument: $argument"
      print -u2 -- ""
      usage
      exit 1
      ;;
  esac
done

typeset -a failures=()
typeset -a swift_command=()

detect_swift_command() {
  if command -v swiftly >/dev/null 2>&1; then
    swift_command=(swiftly run swift)
    return
  fi

  if command -v swift >/dev/null 2>&1; then
    swift_command=(swift)
    return
  fi

  print -u2 -- "Missing required command: swiftly or swift"
  exit 1
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    print -u2 -- "Missing required command: $name"
    exit 1
  fi
}

run_step() {
  local title="$1"
  local workdir="$2"
  shift 2

  print ""
  print -- "==> $title"

  if (
    cd "$workdir"
    "$@"
  ); then
    print -- "PASS: $title"
  else
    print -u2 -- "FAIL: $title"
    failures+=("$title")
  fi
}

run_function_step() {
  local title="$1"
  shift

  print ""
  print -- "==> $title"

  if "$@"; then
    print -- "PASS: $title"
  else
    print -u2 -- "FAIL: $title"
    failures+=("$title")
  fi
}

check_swift_environment() {
  local version_output
  version_output="$("${swift_command[@]}" --version 2>&1)"
  print -- "$version_output"

  if [[ "$version_output" != *"Swift version 6.3"* && "$version_output" != *"Apple Swift version 6.3"* ]]; then
    print -u2 -- ""
    print -u2 -- "Expected Swift 6.3.x for this repository."
    print -u2 -- "Use 'swiftly run swift ...' directly, or make sure 'swift' resolves to the swiftly-managed toolchain."
    return 1
  fi
}

check_bun_environment() {
  bun --version
}

detect_swift_command
require_command bun

run_function_step "Check Swift toolchain" check_swift_environment
run_function_step "Check Bun availability" check_bun_environment

if [[ -f "$repo_root/package.json" && -f "$repo_root/bun.lock" && $skip_bun_install -eq 0 ]]; then
  run_step \
    "Install Bun workspace dependencies" \
    "$repo_root" \
    bun install --frozen-lockfile
fi

run_step \
  "Check public-surface policies" \
  "$repo_root" \
  ./Scripts/check_public_surface_policies.zsh

run_step \
  "Check concurrency-safety policies" \
  "$repo_root" \
  ./Scripts/check_concurrency_safety_policies.zsh

run_step \
  "Run root SwiftPM tests" \
  "$repo_root" \
  "${swift_command[@]}" test

run_step \
  "Run Runners/TerminalUICLI tests" \
  "$repo_root" \
  "${swift_command[@]}" test --package-path Runners/TerminalUICLI

run_step \
  "Run Runners/TerminalUIWASI tests" \
  "$repo_root" \
  "${swift_command[@]}" test --package-path Runners/TerminalUIWASI

run_step \
  "Run GUI/SwiftUITUIGUI tests" \
  "$repo_root" \
  "${swift_command[@]}" test --package-path GUI/SwiftUITUIGUI

run_step \
  "Run GUI/WebTUIGUI Bun tests" \
  "$repo_root/GUI/WebTUIGUI" \
  bun test

run_step \
  "Run Examples/gallery tests" \
  "$repo_root" \
  "${swift_command[@]}" test --package-path Examples/gallery

run_step \
  "Run Examples/WebExample Bun tests" \
  "$repo_root/Examples/WebExample" \
  bun test

print ""

if (( ${#failures[@]} == 0 )); then
  print -- "All repo tests succeeded."
  exit 0
fi

print -u2 -- "Repo test failures:"
for failure in "${failures[@]}"; do
  print -u2 -- "  - $failure"
done

exit 1
