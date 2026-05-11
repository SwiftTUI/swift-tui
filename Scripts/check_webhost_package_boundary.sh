#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

fail() {
  printf '[check_webhost_package_boundary] %s\n' "$1" >&2
  exit 1
}

if rg -n --fixed-strings 'SwiftTUIWebHost' Platforms/CLI/Sources Sources \
  --glob '*.swift'
then
  fail 'SwiftTUIWebHost must not be referenced by root SwiftTUI sources or Platforms/CLI sources.'
fi

if rg -n --fixed-strings 'FlyingFox' Platforms/CLI/Sources Sources \
  --glob '*.swift'
then
  fail 'FlyingFox must only be referenced by the WebHost target.'
fi

cli_target_block=$(
  awk '
    /\.target\(/ { collecting = 1; block = $0; next }
    collecting { block = block "\n" $0 }
    collecting && /name: "SwiftTUICLI"/ { wanted = 1 }
    wanted && /path: "Platforms\/CLI\/Sources\/SwiftTUICLI"/ { print block; exit }
  ' Package.swift
)

case "$cli_target_block" in
  *SwiftTUIWebHost*|*FlyingFox*)
    fail 'The SwiftTUICLI target must not depend on SwiftTUIWebHost or FlyingFox.'
    ;;
esac

webhost_target_block=$(
  awk '
    /\.target\(/ { collecting = 1; block = $0; wanted = 0; next }
    collecting { block = block "\n" $0 }
    collecting && /name: "SwiftTUIWebHost"/ { wanted = 1 }
    wanted && /swiftSettings: swiftSettings\(\)/ { print block; exit }
  ' Package.swift
)

case "$webhost_target_block" in
  *FlyingFox*) ;;
  *) fail 'The SwiftTUIWebHost target should be the root package target that links FlyingFox.' ;;
esac

case "$webhost_target_block" in
  *'Resources/browser'*) ;;
  *) fail 'The SwiftTUIWebHost target should own the browser resources.' ;;
esac

if ! rg -n --fixed-strings --quiet -- 'SwiftTUIWebHostCLI' Package.swift; then
  fail 'The root Package.swift should expose SwiftTUIWebHostCLI.'
fi

if find Sources Platforms/CLI -path '*Resources/browser*' -print | grep .
then
  fail 'Browser resources must only live under Platforms/WebHost.'
fi

printf '[check_webhost_package_boundary] ok\n'
