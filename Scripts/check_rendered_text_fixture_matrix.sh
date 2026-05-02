#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

failures=0

fail() {
  >&2 echo "$1"
  failures=1
}

fixture_support="Tests/SwiftTUITests/Support/RenderedTextFixtureSupport.swift"
fixtures_root="Tests/SwiftTUITests/Fixtures"

expected_fixture_manifest=$(
  rg -o 'init\(name: "[^"]+"' "$fixture_support" \
    | sed -E 's/.*"([^"]+)"/\1.txt/' \
    | LC_ALL=C sort
)

if [ -z "$expected_fixture_manifest" ]; then
  fail "Could not infer the supported rendered-text fixture matrix from $fixture_support."
fi

fixture_directories=$(
  find "$fixtures_root" -mindepth 1 -maxdepth 1 -type d \
    | LC_ALL=C sort
)

if [ -z "$fixture_directories" ]; then
  fail "No rendered-text fixture directories were found in $fixtures_root."
fi

OLD_IFS=$IFS
IFS='
'
for directory in $fixture_directories; do
  actual_fixture_manifest=$(
    cd "$directory" \
      && find . -maxdepth 1 -type f -name '*.txt' \
      | sed 's|^\./||' \
      | LC_ALL=C sort
  )

  if [ "$expected_fixture_manifest" != "$actual_fixture_manifest" ]; then
    fail "$directory must contain exactly the supported terminal configuration fixtures."
    >&2 echo "Expected fixture file set for $directory:"
    >&2 printf '%s\n' "$expected_fixture_manifest"
    >&2 echo "Actual fixture file set for $directory:"
    >&2 printf '%s\n' "$actual_fixture_manifest"
  fi
done
IFS=$OLD_IFS

if [ "$failures" -ne 0 ]; then
  exit 1
fi
