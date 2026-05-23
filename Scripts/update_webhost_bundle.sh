#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
web_checkout=""

usage() {
  cat <<'EOF'
Usage: Scripts/update_webhost_bundle.sh --web-checkout PATH

Builds the browser runtime from SwiftTUI/swift-tui-web and copies the output
into SwiftTUIWebHost's checked-in SwiftPM resource bundle.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --web-checkout)
      web_checkout=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[ -n "$web_checkout" ] || {
  echo "Missing --web-checkout" >&2
  usage >&2
  exit 1
}

web_checkout="$(cd "$web_checkout" && pwd)"
dist_dir="$web_checkout/packages/web/dist"
resource_dir="$repo_root/Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser"

(cd "$web_checkout" && bun install --frozen-lockfile && bun run build:web)

[ -f "$dist_dir/index.html" ] || {
  echo "Missing $dist_dir/index.html" >&2
  exit 1
}

rm -rf "$resource_dir"
mkdir -p "$resource_dir"
cp -R "$dist_dir"/. "$resource_dir"/

find "$resource_dir" -type f -name '*.js' -print | grep -q . || {
  echo "Browser bundle does not contain JavaScript" >&2
  exit 1
}

printf '[update_webhost_bundle] copied %s to %s\n' "$dist_dir" "$resource_dir"
