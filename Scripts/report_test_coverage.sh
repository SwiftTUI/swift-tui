#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

swiftly run swift test --enable-code-coverage "$@"
coverage_json=$(swiftly run swift test --show-codecov-path)

echo "Coverage JSON: $coverage_json"

if [ ! -f "$coverage_json" ]; then
  >&2 echo "SwiftPM did not produce the expected coverage JSON."
  exit 1
fi

line_coverage=$(
  awk '
    match($0, /"lines"[[:space:]]*:[[:space:]]*\{[^}]*"percent"[[:space:]]*:[[:space:]]*[0-9.]+/) {
      value = substr($0, RSTART, RLENGTH)
      sub(/^.*"percent"[[:space:]]*:[[:space:]]*/, "", value)
      print value
      exit
    }
  ' "$coverage_json"
)

if [ -n "$line_coverage" ]; then
  echo "Line coverage: $line_coverage%"
else
  echo "Line coverage: unavailable in SwiftPM coverage JSON"
fi
