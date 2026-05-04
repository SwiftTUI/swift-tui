#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

matches=$(
  rg -n \
    --glob '*.swift' \
    --glob '!Sources/Vendor/**' \
    --glob '!**/.build/**' \
    --glob '!**/.swiftpm/**' \
    --regexp '@unchecked Sendable' \
    --regexp 'nonisolated\(unsafe\)' \
    Sources Tests Platforms Examples Package.swift || true
)

if [ -n "$matches" ]; then
  >&2 echo "Structured concurrency escape hatches are forbidden in checked-in Swift sources."
  >&2 echo "Replace @unchecked Sendable or nonisolated(unsafe) with actor isolation, Sendable-safe storage, or Synchronization primitives."
  >&2 echo ""
  >&2 echo "$matches"
  exit 1
fi
