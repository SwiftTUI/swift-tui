#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

declared_targets=$(mktemp "/tmp/swift-tui-declared-test-targets.XXXXXX")
covered_targets=$(mktemp "/tmp/swift-tui-covered-test-targets.XXXXXX")
missing_targets=$(mktemp "/tmp/swift-tui-missing-test-targets.XXXXXX")
extra_targets=$(mktemp "/tmp/swift-tui-extra-test-targets.XXXXXX")

cleanup() {
  rm -f "$declared_targets" "$covered_targets" "$missing_targets" "$extra_targets"
}

trap cleanup EXIT

awk '
  /\.testTarget\(/ {
    in_test_target = 1
  }

  in_test_target && /name:[[:space:]]*"[^"]+"/ {
    line = $0
    sub(/^.*name:[[:space:]]*"/, "", line)
    sub(/".*$/, "", line)
    print line
    in_test_target = 0
  }
' Package.swift | LC_ALL=C sort -u >"$declared_targets"

awk '
  {
    for (field_index = 1; field_index <= NF; field_index += 1) {
      if ($field_index == "--filter" && (field_index + 1) <= NF) {
        target = $(field_index + 1)
        gsub(/["\\]/, "", target)
        if (target ~ /^[A-Za-z0-9_]+Tests$/) {
          print target
        }
      }
    }
  }
' Scripts/test_all.sh | LC_ALL=C sort -u >"$covered_targets"

comm -23 "$declared_targets" "$covered_targets" >"$missing_targets"
comm -13 "$declared_targets" "$covered_targets" >"$extra_targets"

if [ -s "$missing_targets" ] || [ -s "$extra_targets" ]; then
  if [ -s "$missing_targets" ]; then
    >&2 echo "Root test targets declared in Package.swift but not covered by Scripts/test_all.sh:"
    >&2 sed 's/^/  - /' "$missing_targets"
  fi

  if [ -s "$extra_targets" ]; then
    >&2 echo "Scripts/test_all.sh filters test targets not declared in Package.swift:"
    >&2 sed 's/^/  - /' "$extra_targets"
  fi

  exit 1
fi

echo "All root Package.swift test targets are covered by Scripts/test_all.sh."
