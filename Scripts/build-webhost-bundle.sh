#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '[build-webhost-bundle] %s\n' "$1" >&2
  exit 1
}

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
web_dir="$repo_root/Platforms/Web"
dist_dir="$web_dir/dist"
resource_dir="$repo_root/Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser"

rm -rf "$dist_dir"
(cd "$web_dir" && bun run build:web)

[ -d "$dist_dir" ] || fail "Platforms/Web/dist was not created."
[ -f "$dist_dir/index.html" ] || fail "Platforms/Web/dist/index.html was not created."

rm -rf "$resource_dir"
mkdir -p "$resource_dir"
cp -R "$dist_dir"/. "$resource_dir"/

if ! find "$resource_dir" -type f -print | grep -q .; then
  fail "browser resource bundle is empty."
fi

if ! find "$resource_dir" -type f -name '*.js' -print | grep -q .; then
  fail "browser resource bundle does not contain a JavaScript asset."
fi

printf '[build-webhost-bundle] copied browser bundle to %s\n' "$resource_dir"
