#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

skip_clean=0
skip_bun_install=0
failures=""

usage() {
  cat <<'EOF'
Usage: Scripts/check_demo_builds.sh [--skip-clean] [--skip-bun-install]

Builds the repository's demo packages and host shells, then runs stack-safety
input harnesses against the terminal examples:
  - Examples/canvas
  - Examples/gallery
  - Examples/layouts
  - Examples/SwiftUIExample/TerminalApp
  - Examples/WebExample/TerminalApp
  - Examples/WebHostExample
  - Platforms/WebHost
  - Platforms/SwiftUI
  - Examples/SwiftUIExample/SwiftUIExample.xcodeproj
  - Examples/WebExample (Bun build)
  - Platforms/Web against WebExampleApp

The script also checks required environment dependencies up front:
  - Swift availability
  - Bun availability
  - Python 3 availability
  - Xcode availability
  - Bun workspace dependencies via `bun install --frozen-lockfile` at the repo root

By default the script runs fresh builds. Pass --skip-clean to reuse existing
build artifacts, or --skip-bun-install to reuse the existing Bun install state.
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
    --skip-clean)
      skip_clean=1
      ;;
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

require_command() {
  name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    >&2 echo "Missing required command: $name"
    exit 1
  fi
}

require_command swift
require_command bun
require_command python3
require_command xcodebuild

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

if [ -f "$repo_root/package.json" ] && [ -f "$repo_root/bun.lock" ] && [ "$skip_bun_install" -eq 0 ]; then
  run_step \
    "Install Bun workspace dependencies" \
    "$repo_root" \
    bun install --frozen-lockfile
fi

if [ "$skip_clean" -eq 0 ]; then
  for package_path in \
    "Examples/canvas" \
    "Examples/gallery" \
    "Examples/layouts" \
    "Examples/SwiftUIExample/TerminalApp" \
    "Examples/WebExample/TerminalApp" \
    "Examples/WebHostExample" \
    "Platforms/WebHost" \
    "Platforms/SwiftUI"; do
    run_step \
      "Clean $package_path" \
      "$repo_root" \
      swift package clean --package-path "$package_path"
  done
fi

run_step \
  "Build Examples/canvas" \
  "$repo_root" \
  swift build --package-path Examples/canvas

run_step \
  "Build Examples/canvas (release)" \
  "$repo_root" \
  swift build -c release --package-path Examples/canvas

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
  "Build Examples/layouts" \
  "$repo_root" \
  swift build --package-path Examples/layouts

run_step \
  "Build Examples/layouts (release)" \
  "$repo_root" \
  swift build -c release --package-path Examples/layouts

run_step \
  "Build Examples/SwiftUIExample/TerminalApp" \
  "$repo_root" \
  swift build --package-path Examples/SwiftUIExample/TerminalApp

run_step \
  "Build Examples/WebExample/TerminalApp" \
  "$repo_root" \
  swift build --package-path Examples/WebExample/TerminalApp

run_step \
  "Build Examples/WebHostExample" \
  "$repo_root" \
  swift build --package-path Examples/WebHostExample

run_step \
  "Test Examples/WebHostExample" \
  "$repo_root" \
  swift test --package-path Examples/WebHostExample

run_step \
  "Build Platforms/WebHost" \
  "$repo_root" \
  swift build --package-path Platforms/WebHost

run_step \
  "Build Platforms/SwiftUI" \
  "$repo_root" \
  swift build --package-path Platforms/SwiftUI

if [ "$skip_clean" -eq 0 ]; then
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
  "Build Platforms/Web host with WebExampleApp" \
  "$repo_root/Platforms/Web" \
  bun run build -- --package-path ../../Examples/WebExample/TerminalApp --app WebExampleApp

echo ""

if [ -z "$failures" ]; then
  echo "All demo builds succeeded."
  exit 0
fi

>&2 echo "Demo build failures:"
OLD_IFS=$IFS
IFS='
'
for failure in $failures; do
  >&2 echo "  - $failure"
done
IFS=$OLD_IFS

exit 1
