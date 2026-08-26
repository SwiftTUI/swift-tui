#!/usr/bin/env sh
# Purges the SwiftPM build products of every module downstream of <module>.
#
# SwiftPM does not always invalidate a consumer's objects when a struct in a
# module it depends on gains a stored field: after `SwiftTUIGraph` grew a
# field, stale `SwiftTUICore`/`SwiftTUIViews` objects segfaulted in
# `ResolveContext.init` until their products were purged (plan
# 2026-08-25-002 §12.1, plan 2026-08-25-003 P4). `Scripts/test_all.sh --clean`
# deletes every `.build`; this is the surgical form: it removes only the
# `<Dependent>.build` directories and `Modules/<Dependent>.*` products of the
# modules that depend on <module>, in every configuration and triple, in the
# root package and in the sibling packages that build against it
# (`Tools/TermUIPerf`, `Platforms/*`).
#
# Usage: Scripts/purge_downstream_build_products.sh <module> [--dry-run]
#   <module>    a target name from Package.swift, e.g. SwiftTUIGraph
#   --dry-run   print what would be removed without removing it
#
# In a sibling package's scratch every target of that package is purged as
# well: they all consume swift-tui by path, so they are downstream of any
# module named here even though the root package graph does not list them.
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

module=""
dry_run=0
for argument in "$@"; do
  case "$argument" in
  --dry-run) dry_run=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    >&2 echo "Unknown argument: $argument"
    usage >&2
    exit 2
    ;;
  *)
    if [ -n "$module" ]; then
      >&2 echo "Only one module may be named."
      exit 2
    fi
    module=$argument
    ;;
  esac
done
if [ -z "$module" ]; then
  usage >&2
  exit 2
fi

cd "$repo_root"
downstream=$(
  swiftly run swift package describe --type json \
    | bun run Scripts/lib/downstream_targets.ts "$module"
)
if [ -z "$downstream" ]; then
  echo "No target depends on $module; nothing to purge."
  exit 0
fi

echo "Modules downstream of $module:"
printf '  %s\n' $downstream

remove() {
  if [ "$dry_run" -eq 1 ]; then
    echo "would remove $1"
  else
    echo "removing $1"
    rm -rf "$1"
  fi
}

removed=0
# Every SwiftPM scratch that builds the root package's targets: the root
# `.build`, plus sibling packages that depend on swift-tui by path. A
# sibling's own targets are downstream of everything in swift-tui they
# consume, so its scratch purges them too (they are not in the root graph).
for build_dir in \
  "$repo_root/.build" \
  "$repo_root"/Tools/*/.build \
  "$repo_root"/Platforms/*/.build; do
  [ -d "$build_dir" ] || continue
  scratch_targets=$downstream
  package_dir=$(dirname "$build_dir")
  if [ "$package_dir" != "$repo_root" ] && [ -f "$package_dir/Package.swift" ]; then
    sibling_targets=$(
      cd "$package_dir" \
        && swiftly run swift package describe --type json 2>/dev/null \
        | bun run "$repo_root/Scripts/lib/downstream_targets.ts" --all
    )
    scratch_targets="$downstream
$sibling_targets"
  fi
  # `<triple>/<config>` (and `index-build/<triple>/<config>`) product roots.
  for products in \
    "$build_dir"/*/debug "$build_dir"/*/release \
    "$build_dir"/index-build/*/debug "$build_dir"/index-build/*/release; do
    [ -d "$products" ] || continue
    for target in $scratch_targets; do
      for path in \
        "$products/$target.build" \
        "$products/$target.swiftmodule" \
        "$products/Modules/$target.swiftmodule" \
        "$products/Modules/$target.swiftdoc" \
        "$products/Modules/$target.swiftsourceinfo" \
        "$products/Modules/$target.abi.json" \
        "$products/lib$target.a"; do
        if [ -e "$path" ]; then
          remove "$path"
          removed=$((removed + 1))
        fi
      done
    done
  done
done

if [ "$removed" -eq 0 ]; then
  echo "No build products of the downstream modules were found."
elif [ "$dry_run" -eq 1 ]; then
  echo "$removed product paths would be removed (dry run)."
else
  echo "$removed product paths removed; the next build re-emits them."
fi
