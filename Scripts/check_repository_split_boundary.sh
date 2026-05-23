#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fail() {
  printf '[check_repository_split_boundary] %s\n' "$1" >&2
  exit 1
}

if ! rg -n --fixed-strings --quiet 'SwiftTUIWebHostCLI' Package.swift; then
  fail 'SwiftTUI must keep the combined terminal/WebHost runner in the main Swift package.'
fi

if ! rg -n --fixed-strings --quiet 'SwiftTUIAnimatedImage' Package.swift; then
  fail 'SwiftTUI must keep animated image support in the convenience product.'
fi

if rg -n --fixed-strings '@swifttui/web' Sources Platforms/CLI Platforms/WASI Platforms/Embedding --glob '*.swift'; then
  fail 'Swift source must not depend on the npm browser package.'
fi

if [ ! -f Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser/index.html ]; then
  fail 'SwiftTUIWebHost must ship a checked-in browser bundle.'
fi

if ! find Platforms/WebHost/Sources/SwiftTUIWebHost/Resources/browser -type f -name '*.js' -print | grep -q .; then
  fail 'SwiftTUIWebHost browser bundle must include a JavaScript asset.'
fi

printf '[check_repository_split_boundary] ok\n'
