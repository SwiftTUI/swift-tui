#!/usr/bin/env zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

skip_clean=0

usage() {
  cat <<'EOF'
Usage: Scripts/check_demo_builds.zsh [--skip-clean]

Builds the repository's demo packages and host shells, then runs stack-safety
input harnesses against the terminal examples:
  - Examples/gallery
  - Examples/SwiftUIExample/TerminalApp
  - Examples/WebExample/TerminalApp
  - GUI/SwiftUITUIGUI
  - Examples/SwiftUIExample/SwiftUIExample.xcodeproj
  - Examples/WebExample (Bun build)
  - GUI/WebTUIGUI against WebExampleApp

By default the script runs fresh builds. Pass --skip-clean to reuse existing
build artifacts.
EOF
}

for argument in "$@"; do
  case "$argument" in
    --skip-clean)
      skip_clean=1
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

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    print -u2 -- "Missing required command: $name"
    exit 1
  fi
}

require_command swift
require_command bun
require_command python3
require_command xcodebuild

typeset -a failures=()

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

typeset -a cleanable_swift_packages=(
  "Examples/gallery"
  "Examples/SwiftUIExample/TerminalApp"
  "Examples/WebExample/TerminalApp"
  "GUI/SwiftUITUIGUI"
)

if (( skip_clean == 0 )); then
  for package_path in "${cleanable_swift_packages[@]}"; do
    run_step \
      "Clean $package_path" \
      "$repo_root" \
      swift package clean --package-path "$package_path"
  done
fi

run_step \
  "Build Examples/gallery" \
  "$repo_root" \
  swift build --package-path Examples/gallery

run_step \
  "Build Examples/gallery (release)" \
  "$repo_root" \
  swift build -c release --package-path Examples/gallery

run_step \
  "Stack safety Examples/gallery (debug)" \
  "$repo_root" \
  python3 Scripts/stack_safety_harness.py \
    --binary Examples/gallery/.build/debug/gallery-demo \
    --count 20

run_step \
  "Stack safety Examples/gallery (release)" \
  "$repo_root" \
  python3 Scripts/stack_safety_harness.py \
    --binary Examples/gallery/.build/release/gallery-demo \
    --count 20

run_step \
  "Build Examples/SwiftUIExample/TerminalApp" \
  "$repo_root" \
  swift build --package-path Examples/SwiftUIExample/TerminalApp

run_step \
  "Build Examples/WebExample/TerminalApp" \
  "$repo_root" \
  swift build --package-path Examples/WebExample/TerminalApp

run_step \
  "Build GUI/SwiftUITUIGUI" \
  "$repo_root" \
  swift build --package-path GUI/SwiftUITUIGUI

if (( skip_clean == 0 )); then
  run_step \
    "Build Examples/SwiftUIExample macOS app" \
    "$repo_root" \
    xcodebuild \
      -project Examples/SwiftUIExample/SwiftUIExample.xcodeproj \
      -scheme SwiftUIExample \
      -configuration Debug \
      -destination generic/platform=macOS \
      clean build
else
  run_step \
    "Build Examples/SwiftUIExample macOS app" \
    "$repo_root" \
    xcodebuild \
      -project Examples/SwiftUIExample/SwiftUIExample.xcodeproj \
      -scheme SwiftUIExample \
      -configuration Debug \
      -destination generic/platform=macOS \
      build
fi

run_step \
  "Build Examples/WebExample web demo" \
  "$repo_root/Examples/WebExample" \
  bun run build

run_step \
  "Build GUI/WebTUIGUI host with WebExampleApp" \
  "$repo_root/GUI/WebTUIGUI" \
  bun run build -- --package-path ../../Examples/WebExample/TerminalApp --app WebExampleApp

print ""

if (( ${#failures[@]} == 0 )); then
  print -- "All demo builds succeeded."
  exit 0
fi

print -u2 -- "Demo build failures:"
for failure in "${failures[@]}"; do
  print -u2 -- "  - $failure"
done

exit 1
