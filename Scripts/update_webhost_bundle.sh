#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
web_checkout=""
allow_dirty=0

usage() {
  cat <<'EOF'
Usage: Scripts/update_webhost_bundle.sh --web-checkout PATH [--allow-dirty]

Builds the browser runtime from SwiftTUI/swift-tui-web and copies the output
into SwiftTUIWebHost's checked-in SwiftPM resource bundle, recording the web
checkout's revision in bundle-provenance.json (the coordination root's
webhost_bundle_provenance gate compares that stamp against the pinned
swift-tui-web submodule to detect stale vendored bundles).

--allow-dirty skips the clean-checkout requirement; the provenance stamp then
records a "-dirty" describe and cannot be trusted by the staleness gate.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --web-checkout)
      web_checkout=$2
      shift 2
      ;;
    --allow-dirty)
      allow_dirty=1
      shift
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
resource_dir="$repo_root/Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser"

if [ "$allow_dirty" -ne 1 ] && [ -n "$(git -C "$web_checkout" status --porcelain)" ]; then
  echo "swift-tui-web checkout is dirty; commit first so the provenance stamp is" >&2
  echo "trustworthy, or pass --allow-dirty for a local-only experiment." >&2
  exit 1
fi

# Build into a fresh directory: the web package's default dist directories
# accumulate previously hashed bundles, and copying those stale siblings into
# the resource bundle would ship two runtimes.
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/webhost-bundle.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

(cd "$web_checkout" && bun install --frozen-lockfile)
(cd "$web_checkout/packages/web" && bun run cli.ts build:web --dist "$build_dir")

[ -f "$build_dir/index.html" ] || {
  echo "Missing $build_dir/index.html" >&2
  exit 1
}

rm -rf "$resource_dir"
mkdir -p "$resource_dir"
cp -R "$build_dir"/. "$resource_dir"/

find "$resource_dir" -type f -name '*.js' -print | grep -q . || {
  echo "Browser bundle does not contain JavaScript" >&2
  exit 1
}

web_revision="$(git -C "$web_checkout" rev-parse HEAD)"
web_describe="$(git -C "$web_checkout" describe --tags --always --dirty)"
built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$resource_dir/bundle-provenance.json" <<EOF
{
  "webRevision": "$web_revision",
  "webDescribe": "$web_describe",
  "builtAt": "$built_at"
}
EOF

printf '[update_webhost_bundle] copied %s to %s (swift-tui-web %s)\n' \
  "$build_dir" "$resource_dir" "$web_describe"
