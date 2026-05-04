#!/usr/bin/env sh

# Forbid bare `Thread.isMainThread` outside of justified call sites.
#
# `Thread.isMainThread` is not a portable proxy for main-actor isolation.
# On Linux's swift-corelibs Foundation it returns `false` for code
# synchronously invoked from `@MainActor` context, even though that code is
# provably on the main actor's executor. See LINUX_ISSUES.md issue #2.
#
# Use the portable `currentlyOnMainActor()` helper in
# Tests/SwiftTUITests/Support/MainActorTestSupport.swift instead. If you
# genuinely need `Thread.isMainThread` (e.g. you're implementing the helper
# itself, or you specifically want to know "is this the OS main thread?"
# regardless of actor isolation), justify the call site with a
# `thread-ismain-ok:` comment within the same line or the 3 lines above it,
# explaining why.
#
# Example of an acceptable use:
#
#     // thread-ismain-ok: bridging into a C API that requires us to be
#     // on the OS main thread; we don't care about Swift actor isolation.
#     guard Thread.isMainThread else { ... }

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

# Justification policy: the marker `thread-ismain-ok:` may appear either
# on the same line as the call, or anywhere inside the *contiguous* comment
# block (no blank lines, no code lines) immediately preceding the call.
# This lets multi-line explanations span as many lines as needed without
# an arbitrary line-count cap, while still requiring the comment to be
# adjacent enough to the call that a reader sees them together.

# Find every Swift file that mentions Thread.isMainThread (excluding the
# usual non-source dirs). For each, walk the file and emit one line per
# unjustified hit.
files=$(
  rg -l --no-messages \
    --glob '*.swift' \
    --glob '!Vendor/**' \
    --glob '!**/.build/**' \
    --glob '!**/.swiftpm/**' \
    --glob '!**/.build-linux/**' \
    --glob '!Sources/Vendor/**' \
    'Thread\.isMainThread' \
    Sources Tests Platforms Examples 2>/dev/null || true
)

if [ -z "$files" ]; then
  exit 0
fi

violations=$(
  printf '%s\n' "$files" | while IFS= read -r file; do
    [ -n "$file" ] || continue
    awk -v file="$file" '
      {
        lines[NR] = $0
      }
      END {
        for (n = 1; n <= NR; n++) {
          line = lines[n]
          # Skip references inside `//` line comments. They name
          # Thread.isMainThread (this script and our docs do that) but do
          # not call it. We approximate "real call" as: with line comments
          # stripped, the call still appears.
          stripped = line
          sub(/\/\/.*$/, "", stripped)
          if (stripped !~ /Thread\.isMainThread/) continue

          # Same-line marker counts.
          ok = (line ~ /thread-ismain-ok:/)

          # Otherwise, walk backwards through the contiguous block of
          # comment-only / blank lines and accept any marker found there.
          # Stop as soon as we hit a non-comment, non-blank line.
          if (!ok) {
            for (i = n - 1; i >= 1; i--) {
              prev = lines[i]
              trimmed = prev
              sub(/^[ \t]+/, "", trimmed)
              # Allow blank lines inside comment blocks (some authors space
              # paragraphs); stop at the first line that is neither blank
              # nor a `//` comment.
              if (trimmed != "" && trimmed !~ /^\/\//) break
              if (prev ~ /thread-ismain-ok:/) {
                ok = 1
                break
              }
            }
          }

          if (!ok) {
            printf "%s:%d: %s\n", file, n, line
          }
        }
      }
    ' "$file"
  done
)

if [ -n "$violations" ]; then
  >&2 echo "Bare Thread.isMainThread is forbidden — it is not a portable proxy"
  >&2 echo "for main-actor isolation (see LINUX_ISSUES.md issue #2)."
  >&2 echo ""
  >&2 echo "In tests, prefer:"
  >&2 echo "  currentlyOnMainActor()"
  >&2 echo "    from Tests/SwiftTUITests/Support/MainActorTestSupport.swift"
  >&2 echo ""
  >&2 echo "If you genuinely need Thread.isMainThread, justify the call site"
  >&2 echo "with a 'thread-ismain-ok:' comment on the same line, or anywhere"
  >&2 echo "in the contiguous comment block immediately above it, explaining"
  >&2 echo "why thread identity is the right question (and not actor isolation)."
  >&2 echo ""
  >&2 echo "Unjustified call sites:"
  >&2 printf '%s\n' "$violations"
  exit 1
fi
