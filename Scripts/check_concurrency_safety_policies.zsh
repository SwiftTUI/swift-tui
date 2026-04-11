#!/usr/bin/env zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

matches="$(
  rg -n \
    --glob '*.swift' \
    --glob '!Sources/Vendor/**' \
    --glob '!**/.build/**' \
    --glob '!**/.swiftpm/**' \
    --regexp '@unchecked Sendable' \
    --regexp 'nonisolated\(unsafe\)' \
    Sources Tests Runners GUI Examples Package.swift || true
)"

if [[ -n "$matches" ]]; then
  print -u2 -- "Structured concurrency escape hatches are forbidden in checked-in Swift sources."
  print -u2 -- "Replace @unchecked Sendable or nonisolated(unsafe) with actor isolation, Sendable-safe storage, or Synchronization primitives."
  print -u2 -- ""
  print -u2 -- "$matches"
  exit 1
fi
