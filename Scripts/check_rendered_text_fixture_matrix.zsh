#!/usr/bin/env zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0

fail() {
  print -u2 -- "$1"
  failures=1
}

fixture_support="Tests/TerminalUITests/Support/RenderedTextFixtureSupport.swift"
fixtures_root="Tests/TerminalUITests/Fixtures"

expected_fixture_files=("${(@f)$(rg -o 'init\(name: "[^"]+"' "$fixture_support" | sed -E 's/.*"([^"]+)"/\1.txt/' | LC_ALL=C sort)}")

if (( ${#expected_fixture_files[@]} == 0 )); then
  fail "Could not infer the supported rendered-text fixture matrix from $fixture_support."
fi

fixture_directories=("${(@f)$(find "$fixtures_root" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)}")

if (( ${#fixture_directories[@]} == 0 )); then
  fail "No rendered-text fixture directories were found in $fixtures_root."
fi

for directory in "${fixture_directories[@]}"; do
  actual_fixture_files=("${(@f)$(cd "$directory" && find . -maxdepth 1 -type f -name '*.txt' | sed 's|^\./||' | LC_ALL=C sort)}")
  expected_fixture_manifest="$(printf '%s\n' "${expected_fixture_files[@]}" | LC_ALL=C sort)"
  actual_fixture_manifest="$(printf '%s\n' "${actual_fixture_files[@]}")"

  if [[ "$expected_fixture_manifest" != "$actual_fixture_manifest" ]]; then
    fail "$directory must contain exactly the supported terminal configuration fixtures."
    print -u2 -- "Expected fixture file set for $directory:"
    printf '%s\n' "$expected_fixture_manifest" >&2
    print -u2 -- "Actual fixture file set for $directory:"
    printf '%s\n' "$actual_fixture_manifest" >&2
  fi
done

if (( failures != 0 )); then
  exit 1
fi
