#!/usr/bin/env sh
# Source-level ban, including the convenience product whose host dependencies
# legitimately use Foundation. The module-trace audit checks transitive imports.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"
if rg -n --glob '*.swift' \
  '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*(public[[:space:]]+)?(package[[:space:]]+)?import[[:space:]]+((struct|class|enum|protocol|typealias|func|var|let)[[:space:]]+)?Foundation([[:space:].;]|$)' \
  Sources/SwiftTUIPrimitives Sources/SwiftTUIGraph Sources/SwiftTUICore \
  Sources/SwiftTUIViews Sources/SwiftTUI \
  Vendor/swift-figlet/Sources/EmbeddedFonts Vendor/swift-figlet/Sources/SwiftFiglet; then
  echo 'Foundation imports are forbidden in the Foundation-free library sources.' >&2
  exit 1
else
  status=$?
  [ "$status" -eq 1 ] || exit "$status"
fi
