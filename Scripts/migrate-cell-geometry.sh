#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

usage() {
  cat <<'EOF'
Usage: Scripts/migrate-cell-geometry.sh [--dry-run|--apply]

Mechanically renames layout/raster geometry in an explicit file list:
  Point -> CellPoint
  Size  -> CellSize
  Rect  -> CellRect

The script is intentionally narrow. Pointer, gesture, host input, and GUI files
must be migrated semantically instead of by this bulk rename.

The default is --dry-run. Pass --apply to mutate files and run swift-format on
the touched Swift files.
EOF
}

mode=dry-run
case "${1:---dry-run}" in
  --dry-run)
    mode=dry-run
    ;;
  --apply)
    mode=apply
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

files=$(cat <<'EOF'
Sources/Core/CollectionStylePresentations.swift
Sources/Core/CommitAndFrameTypes.swift
Sources/Core/DrawExtractor+Lists.swift
Sources/Core/DrawExtractor+Tables.swift
Sources/Core/DrawExtractor.swift
Sources/Core/FocusTracker.swift
Sources/Core/Graph/ViewNode.swift
Sources/Core/ImageTypes.swift
Sources/Core/LayoutEngine+Alignment.swift
Sources/Core/LayoutEngine+List.swift
Sources/Core/LayoutEngine+Placement.swift
Sources/Core/LayoutEngine+Stack.swift
Sources/Core/LayoutEngine+Table.swift
Sources/Core/LayoutEngine+Utility.swift
Sources/Core/LayoutEngine.swift
Sources/Core/LayoutTypes.swift
Sources/Core/LocalScrollPositionRegistry.swift
Sources/Core/NodeMetadata.swift
Sources/Core/Pipeline.swift
Sources/Core/RasterTypes.swift
Sources/Core/Rasterizer.swift
Sources/Core/RenderTreeAndSemanticsTypes.swift
Sources/Core/Semantics.swift
Sources/Core/Snapshots.swift
Sources/Core/TextFigureSupport.swift
Sources/Core/TextLayout.swift
EOF
)

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/stui-cell-geometry.XXXXXX")
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

changed_files=
changed_count=0

for file in $files; do
  if [ ! -f "$file" ]; then
    echo "missing expected file: $file" >&2
    exit 1
  fi

  tmp_file="$tmp_dir/$file"
  mkdir -p "$(dirname "$tmp_file")"
  cp "$file" "$tmp_file"
  perl -0pi -e 's/\bPoint\b/CellPoint/g; s/\bSize\b/CellSize/g; s/\bRect\b/CellRect/g' "$tmp_file"

  if ! cmp -s "$file" "$tmp_file"; then
    changed_count=$((changed_count + 1))
    changed_files="${changed_files}${changed_files:+ }$file"
    echo "diff summary for $file:"
    git diff --no-index --stat -- "$file" "$tmp_file" || true

    if [ "$mode" = "apply" ]; then
      cp "$tmp_file" "$file"
    fi
  fi
done

if [ "$changed_count" -eq 0 ]; then
  echo "No layout/raster geometry renames found in the explicit file list."
  exit 0
fi

if [ "$mode" != "apply" ]; then
  echo ""
  echo "Dry run only. Re-run with --apply to mutate $changed_count file(s)."
  exit 1
fi

swift format format -i --configuration .swift-format.json $changed_files
echo "Applied geometry rename to $changed_count file(s)."
