#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fail() {
  printf '[check_graph_render_layering] %s\n' "$1" >&2
  exit 1
}

# Static deny-list scan over the extracted SwiftTUIGraph engine target (Phase
# 2b).  It asserts the graph layer (Resolve/, Runtime/, Pipeline/Scheduler.swift,
# Animation/) never names a render-engine / phase-product / engine-context type
# as code.  The compiler is now the authoritative backstop — SwiftTUIGraph
# depends on SwiftTUIPrimitives only and cannot name a render-Core type — so this
# stays as a belt-and-suspenders guard.  See the boundary manifest in the
# coordination root:
#   docs/plans/2026-07-08-001-graph-render-boundary-manifest.md
# and Phase 1a (the PlacedNode viewport-lifecycle inversion).

# ---- graph-side file set (relative to repo root) ----------------------------
# Every .swift under SwiftTUIGraph's Resolve/ and Runtime/, plus
# Pipeline/Scheduler.swift, plus every .swift under Animation/.
graph_files=()
while IFS= read -r f; do
  graph_files+=("$f")
done < <(
  {
    find Sources/SwiftTUIGraph/Resolve -name '*.swift' -type f
    find Sources/SwiftTUIGraph/Runtime -name '*.swift' -type f
    printf '%s\n' Sources/SwiftTUIGraph/Pipeline/Scheduler.swift
    find Sources/SwiftTUIGraph/Animation -name '*.swift' -type f
  } | sort -u
)

if [ "${#graph_files[@]}" -eq 0 ]; then
  fail 'graph-side file set is empty — expected Resolve/, Runtime/, Pipeline/Scheduler.swift, Animation/.'
fi

# ---- deny set ---------------------------------------------------------------
# Render engine / algorithm / phase-product / context / cache / index names
# that are never legitimate in graph code.  Matched as WHOLE WORDS, so
# `PlacedNode` does not match `PlacedNodeResolvedMetadata`.
deny_types=(
  MeasuredNode
  PlacedNode
  DrawNode
  RasterSurface
  RasterSurfaceFragment
  RasterPresentationLayer
  CommitPlan
  CommitPlanner
  SemanticSnapshot
  SemanticExtractor
  DrawExtractor
  LayoutEngine
  Rasterizer
  RasterizationResult
  SnapshotRenderer
  FocusTracker
  FrameArtifacts
  LayoutPassContext
  MeasurementCache
  TextLayoutCache
  OffscreenFrameElision
  StructuralFrameIndex
  RetainedFrameIndex
  RetainedLayoutSession
)

# ---- allowlist --------------------------------------------------------------
# THIS LIST MUST SHRINK TO EMPTY AT THE END OF PHASE 1a.  Each entry names a
# coupling the migration will invert; DO NOT add entries to widen the boundary.
#
# The one known coupling today is the viewport lifecycle-by-placement seam:
# ViewGraph's finalizeFrame call chain threads a `PlacedNode` down to the
# viewport-lifecycle planner.  Phase 1a inverts it (a `ViewportVisibilitySummary`
# value replaces the `PlacedNode` parameter).  Stored as (file, type) pairs so
# the allowlist is robust to line-number shifts.
allowlist=(
  # EMPTY — Phase 1a inverted the PlacedNode viewport-lifecycle seam
  # (a ViewportVisibilitySummary value now replaces the PlacedNode parameter).
  # The graph/render boundary is clean. DO NOT add entries to widen it.
)

is_allowlisted() {
  file=$1
  type=$2
  [ "${#allowlist[@]}" -eq 0 ] && return 1
  for entry in "${allowlist[@]}"; do
    if [ "$entry" = "$file|$type" ]; then
      return 0
    fi
  done
  return 1
}

# ---- scan -------------------------------------------------------------------
violations=()
for type in "${deny_types[@]}"; do
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    # rg --no-heading --line-number output: path:lineno:content
    path=${hit%%:*}
    rest=${hit#*:}
    lineno=${rest%%:*}
    content=${rest#*:}

    # Left-trim so we can inspect the first non-whitespace character.
    lstripped="${content#"${content%%[![:space:]]*}"}"

    # Pure-comment lines (first non-space char is '/', i.e. // or ///) are not
    # code references — ignore them.  The repo uses only // line comments.
    case "$lstripped" in
    /*) continue ;;
    esac

    # Right-trim for a tidy report line.
    trimmed="${lstripped%"${lstripped##*[![:space:]]}"}"

    if is_allowlisted "$path" "$type"; then
      continue
    fi

    violations+=("$path:$lineno: references render-engine type '$type' — $trimmed")
  done < <(
    rg --no-heading --line-number --word-regexp --fixed-strings "$type" "${graph_files[@]}" || true
  )
done

if [ "${#violations[@]}" -gt 0 ]; then
  for v in "${violations[@]}"; do
    printf '%s\n' "$v" >&2
  done
  printf '\n' >&2
  fail "graph-side code (Resolve/, Runtime/, Pipeline/Scheduler.swift, Animation/) must not name render-engine types.
These names belong to the render layer (SwiftTUICore) that graph code (SwiftTUIGraph) must not depend on.
See docs/plans/2026-07-08-001-graph-render-boundary-manifest.md (in the swift-tui-org coordination root) and Phase 1a (the PlacedNode viewport-lifecycle inversion) for how each coupling is removed."
fi

printf '[check_graph_render_layering] ok — graph layer (Resolve/, Runtime/, Pipeline/Scheduler.swift, Animation/) names no render-engine types.\n'
