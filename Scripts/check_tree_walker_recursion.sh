#!/usr/bin/env sh

# D72 tripwire: the frame-tail tree walkers must stay iterative.
#
# The fused frame tail runs on plain DispatchQueue workers with the small
# default Dispatch stack (and synchronously on the caller under WASI, ADR-0020).
# Recursive walkers over unbounded-depth subtrees — node-hosted collection rows,
# deep custom-layout chains — overflow it, release-only and input-shape
# dependent, with no attribution. Two such overflows already shipped and were
# point-fixed individually (45ffdc44, 0ed2028f) before every sibling walker in
# these files was converted.
#
# This is a heuristic tripwire, not a proof. The proof is the deterministic
# small-stack reduction suite (Tests/SwiftTUICoreTests/FrameTailWalkerStackSafetyTests.swift).
# What this adds is that the class cannot silently REOPEN: a newly added
# self-recursive walker in these files, or a tree type whose `==` quietly
# reverts to the synthesized (recursive) form, fails here.
#
# Escape hatch: put `// recursion-allowed: <reason>` on the calling line for a
# helper that genuinely is not a tree walk (bounded depth by construction).
#
# Usage:
#   Scripts/check_tree_walker_recursion.sh              # check this repo
#   Scripts/check_tree_walker_recursion.sh --self-test  # prove the check fails
#                                                       # on planted recursion

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

# Files whose walkers are reachable from the frame tail over unbounded-depth
# subtrees. Deliberately narrow: a repo-wide sweep would drown real findings in
# false positives from bounded helpers. Widen once this has been clean for a
# while (the plan's open question 3).
WATCHED_FILES="Sources/SwiftTUIGraph/Resolve/ResolvedNodeEquivalence.swift
Sources/SwiftTUICore/Measure/LayoutEngine+RetainedLayout.swift
Sources/SwiftTUICore/Place/LayoutEngine+Placement.swift
Sources/SwiftTUICore/Measure/MeasuredNode.swift
Sources/SwiftTUICore/Place/PlacedNode.swift"

# Types whose `==` must stay an explicit, iterative implementation. A field
# added to any of these regenerates a synthesized `==` the moment the explicit
# one is deleted, and a synthesized `==` on a tree struct recurses through its
# children array — invisibly, at every call site.
EQUATABLE_TREE_FILES="Sources/SwiftTUIGraph/Resolve/ResolvedNodeEquivalence.swift
Sources/SwiftTUICore/Measure/MeasuredNode.swift
Sources/SwiftTUICore/Place/PlacedNode.swift"

# Same-name calls that delegate to a DIFFERENT type rather than recursing.
# `ResolvedNode.isEquivalentForPlacement` calls
# `layoutBehavior.isEquivalentForPlacement`, which is `LayoutBehavior`'s own
# non-tree implementation. Adding a receiver here is a decision, not a
# formality: it asserts the callee is not the same tree type.
DELEGATING_RECEIVERS="layoutBehavior drawPayload"

scan_file() {
  file="$1"
  awk -v receivers="$DELEGATING_RECEIVERS" '
    BEGIN {
      split(receivers, receiverList, " ")
      for (i in receiverList) delegating[receiverList[i]] = 1
      depth = 0
      current = ""
    }
    {
      line = $0

      # Strip trailing line comments before brace counting, but remember the
      # escape-hatch tag first. The tag counts on the calling line or the line
      # directly above it, since a tagged call is usually too long to carry a
      # trailing comment as well.
      taggedHere = (line ~ /\/\/[[:space:]]*recursion-allowed:/)
      allowed = (taggedHere || previousTagged)
      previousTagged = taggedHere
      code = line
      sub(/\/\/.*$/, "", code)

      # A function declaration starts a tracked body. Only the outermost
      # function is tracked; a nested helper is not separately tracked, but its
      # braces still count toward the enclosing body.
      if (current == "" && code ~ /(^|[[:space:]])func[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[(<]/) {
        name = code
        sub(/^.*[[:space:]]func[[:space:]]+/, "", name)
        sub(/^func[[:space:]]+/, "", name)
        sub(/[[:space:]]*[(<].*$/, "", name)
        if (name != "" && name != "==") {
          current = name
          startLine = NR
          depth = 0
          # These signatures routinely span several lines, so the body has not
          # opened until the first brace appears. Clearing the tracker on
          # "depth == 0" before then would silently stop watching every
          # multi-line-signature walker — which is most of them.
          opened = 0
        }
      }

      if (current != "") {
        # Look for a call to the enclosing function inside its own body.
        if (opened && NR > startLine && index(code, current "(") > 0) {
          rest = code
          while (index(rest, current "(") > 0) {
            pos = index(rest, current "(")
            before = substr(rest, 1, pos - 1)
            rest = substr(rest, pos + length(current) + 1)

            # Reject matches that are part of a longer identifier.
            prevChar = (pos > 1) ? substr(before, length(before), 1) : ""
            if (prevChar ~ /[A-Za-z0-9_]/) continue

            # Resolve the receiver: the identifier immediately before the dot.
            receiver = ""
            if (prevChar == ".") {
              qualified = before
              sub(/\.$/, "", qualified)
              if (match(qualified, /[A-Za-z_][A-Za-z0-9_]*$/)) {
                receiver = substr(qualified, RSTART, RLENGTH)
              }
            }
            if (receiver != "" && (receiver in delegating)) continue

            if (!allowed) {
              printf "%s:%d: %s calls itself (%s)\n", FILENAME, NR, current, line
              found = 1
            }
          }
        }
      }

      # Brace accounting drives when the tracked body ends.
      opens = gsub(/{/, "{", code)
      closes = gsub(/}/, "}", code)
      if (current != "") {
        depth += opens - closes
        if (opens > 0) {
          opened = 1
        }
        if (opened && depth <= 0) {
          current = ""
          depth = 0
          opened = 0
        }
      }
    }
    END { exit(found ? 1 : 0) }
  ' "$file"
}

run_checks() {
  root="$1"
  failures=0

  for file in $WATCHED_FILES; do
    if [ ! -f "$root/$file" ]; then
      >&2 echo "error: watched walker file is missing: $file"
      failures=$((failures + 1))
      continue
    fi
    if ! (cd "$root" && scan_file "$file"); then
      >&2 echo "error: $file contains a self-recursive tree walker."
      >&2 echo "       Convert it to an explicit stack (see the walkers in this"
      >&2 echo "       file for the shape), or tag the call site with"
      >&2 echo "       '// recursion-allowed: <reason>' if its depth is bounded"
      >&2 echo "       by construction."
      failures=$((failures + 1))
    fi
  done

  for file in $EQUATABLE_TREE_FILES; do
    if [ ! -f "$root/$file" ]; then
      continue
    fi
    if ! grep -q "static func ==" "$root/$file"; then
      >&2 echo "error: $file no longer declares an explicit 'static func =='."
      >&2 echo "       A tree struct that falls back to the synthesized"
      >&2 echo "       conformance compares its children array recursively."
      failures=$((failures + 1))
    fi

    # An explicit `==` is not enough on its own: comparing the children
    # COLLECTION (`lhs.children == rhs.children`) recurses through Array's
    # elementwise `==`, which is a tree walk with no syntactic self-call to
    # find. Both `ResolvedNode.==` and `PlacedNode.==` were shaped exactly that
    # way. Comparing `children.count` and pushing the pairs is the iterative
    # form and does not match this pattern.
    if grep -nE '\.(children|childMeasurements)[[:space:]]*==' "$root/$file" \
      | grep -v 'recursion-allowed:'; then
      >&2 echo "error: $file compares a children collection directly."
      >&2 echo "       Array equality recurses elementwise — compare"
      >&2 echo "       '.count' and push the child pairs onto the walk stack"
      >&2 echo "       instead."
      failures=$((failures + 1))
    fi
  done

  return $failures
}

self_test() {
  temp_root=$(mktemp -d)
  trap 'rm -rf "$temp_root"' EXIT

  for file in $WATCHED_FILES; do
    mkdir -p "$temp_root/$(dirname "$file")"
    cp "$repo_root/$file" "$temp_root/$file"
  done

  # The unmodified copy must pass, or the check is vacuous.
  if ! run_checks "$temp_root" >/dev/null 2>&1; then
    >&2 echo "error: self-test: an unmodified copy of the walker files failed the check."
    return 1
  fi

  # Plant a self-recursive walker and require the check to catch it.
  planted="$temp_root/Sources/SwiftTUICore/Place/PlacedNode.swift"
  cat >>"$planted" <<'PLANTED'

extension PlacedNode {
  func plantedRecursiveWalker() -> Int {
    1 + children.reduce(0) { $0 + $1.plantedRecursiveWalker() }
  }
}
PLANTED
  if run_checks "$temp_root" >/dev/null 2>&1; then
    >&2 echo "error: self-test: planted recursion was NOT detected."
    return 1
  fi

  # The escape hatch must still work.
  cp "$repo_root/Sources/SwiftTUICore/Place/PlacedNode.swift" "$planted"
  cat >>"$planted" <<'PLANTED'

extension PlacedNode {
  func plantedBoundedWalker(remaining: Int) -> Int {
    guard remaining > 0 else { return 0 }
    // recursion-allowed: bounded by the caller's explicit budget, not by tree depth
    return 1 + plantedBoundedWalker(remaining: remaining - 1)
  }
}
PLANTED
  if ! run_checks "$temp_root" >/dev/null 2>&1; then
    >&2 echo "error: self-test: the 'recursion-allowed' escape hatch did not suppress the finding."
    return 1
  fi

  # And a same-name delegation to another type must not be flagged.
  cp "$repo_root/Sources/SwiftTUICore/Place/PlacedNode.swift" "$planted"
  if ! run_checks "$temp_root" >/dev/null 2>&1; then
    >&2 echo "error: self-test: restoring the original copy failed the check."
    return 1
  fi

  echo "Tree-walker recursion self-test passed."
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit 0
fi

if run_checks "$repo_root"; then
  echo "Tree-walker recursion guardrails passed."
else
  exit 1
fi
