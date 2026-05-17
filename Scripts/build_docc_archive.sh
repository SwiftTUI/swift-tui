#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
targets_file="$repo_root/Scripts/lib/public_docc_targets.txt"
output_path=".build-docs"
hosting_base_path="docs"

usage() {
  cat <<'EOF'
Usage: Scripts/build_docc_archive.sh [--output-path PATH] [--hosting-base-path PATH]

Builds the combined DocC archive for every DocC target listed in
Scripts/lib/public_docc_targets.txt. That manifest must include every externally
linkable root package product, and may include support targets whose symbols are
part of the published reference. Example packages under Examples/ are
intentionally excluded from DocC coverage.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --output-path)
    output_path=$2
    shift 2
    ;;
  --hosting-base-path)
    hosting_base_path=$2
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    >&2 echo "Unknown argument: $1"
    >&2 echo ""
    usage >&2
    exit 1
    ;;
  esac
done

cd "$repo_root"

if [ ! -f "$targets_file" ]; then
  >&2 echo "Missing DocC target manifest: $targets_file"
  exit 1
fi

rm -rf "$output_path"

set -- package \
  --allow-writing-to-directory "$output_path" \
  generate-documentation

while IFS='|' read -r target _catalog; do
  case "$target" in
  '' | \#*)
    continue
    ;;
  esac

  set -- "$@" --target "$target"
done <"$targets_file"

set -- "$@" \
  --enable-experimental-combined-documentation \
  --transform-for-static-hosting \
  --hosting-base-path "$hosting_base_path" \
  --output-path "$output_path"

swiftly run swift "$@"
