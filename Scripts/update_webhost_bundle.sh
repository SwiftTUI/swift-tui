#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
web_checkout=""
allow_dirty=0
web_tag=""
candidate=0

usage() {
  cat <<'EOF'
Usage: Scripts/update_webhost_bundle.sh --web-checkout PATH (--web-tag VERSION | --candidate) [--allow-dirty]

Builds the browser runtime from SwiftTUI/swift-tui-web and copies the output
into SwiftTUIWebHost's checked-in SwiftPM resource bundle, recording the web
selected source, build inputs, contract profiles and resource digests in
bundle-provenance.json. A newer development web revision does not invalidate
this deliberate selection. --web-tag binds a release; --candidate is for
pre-tag integration and cannot satisfy release acceptance.

--allow-dirty skips the clean-checkout requirement; the provenance stamp then
records a dirty candidate and cannot pass provenance verification.
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
    --web-tag)
      web_tag=${2:?--web-tag requires a version}
      shift 2
      ;;
    --candidate)
      candidate=1
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
initial_revision="$(git -C "$web_checkout" rev-parse HEAD)"
[[ ( -n "$web_tag" && "$candidate" -eq 0 ) || ( -z "$web_tag" && "$candidate" -eq 1 ) ]] || {
  echo 'Choose --web-tag VERSION or --candidate' >&2
  exit 1
}
[[ "$allow_dirty" -eq 0 || "$candidate" -eq 1 ]] || {
  echo '--allow-dirty requires --candidate' >&2
  exit 1
}

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
(cd "$web_checkout" && bun run build:packages)
(cd "$web_checkout/packages/web" && bun run cli.ts build:web --renderer canvas --dist "$build_dir")

[ -f "$build_dir/index.html" ] || {
  echo "Missing $build_dir/index.html" >&2
  exit 1
}

find "$build_dir" -type f -name '*.js' -print | grep -q . || {
  echo "Browser bundle does not contain JavaScript" >&2
  exit 1
}

[[ "$(git -C "$web_checkout" rev-parse HEAD)" == "$initial_revision" ]] || {
  echo 'Web source revision changed during the build' >&2
  exit 1
}
selection=(--candidate)
if [[ -n "$web_tag" ]]; then selection=(--web-tag "$web_tag"); fi
if [[ "$allow_dirty" -eq 1 ]]; then selection+=(--allow-dirty); fi
python3 "$repo_root/Scripts/webhost_bundle_provenance.py" create \
  --bundle "$build_dir" --web-checkout "$web_checkout" --bun-version "$(bun --version)" "${selection[@]}"
if [[ "$allow_dirty" -eq 0 ]]; then
  python3 "$repo_root/Scripts/webhost_bundle_provenance.py" verify --bundle "$build_dir" --web-checkout "$web_checkout"
fi

rm -rf "$resource_dir"
mkdir -p "$resource_dir"
cp -R "$build_dir"/. "$resource_dir"/

printf '[update_webhost_bundle] copied %s to %s (swift-tui-web %s)\n' \
  "$build_dir" "$resource_dir" "$initial_revision"
