#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

fail() {
  printf '[check_webhost_package_boundary] %s\n' "$1" >&2
  exit 1
}

if rg -n --fixed-strings 'SwiftTUIWebHost' Package.swift Platforms/CLI Sources \
  --glob '*.swift' --glob 'Package.swift'
then
  fail 'SwiftTUIWebHost must not be referenced by root SwiftTUI, Sources, or Platforms/CLI.'
fi

if rg -n --fixed-strings 'FlyingFox' Package.swift Platforms/CLI Sources \
  --glob '*.swift' --glob 'Package.swift'
then
  fail 'FlyingFox must only be linked from Platforms/WebHost.'
fi

if find Sources Platforms/CLI -path '*Resources/browser*' -print | grep .
then
  fail 'Browser resources must only live under Platforms/WebHost.'
fi

printf '[check_webhost_package_boundary] ok\n'
