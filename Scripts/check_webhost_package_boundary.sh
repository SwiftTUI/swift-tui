#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

fail() {
  printf '[check_webhost_package_boundary] %s\n' "$1" >&2
  exit 1
}

target_block() {
  target_name=$1
  awk -v target_name="$target_name" '
    /\.target\(/ { collecting = 1; block = $0; wanted = 0; next }
    collecting { block = block "\n" $0 }
    collecting && $0 ~ "name: \"" target_name "\"" { wanted = 1 }
    wanted && /swiftSettings: swiftSettings\(\)/ { print block; exit }
  ' Package.swift
}

if rg -n --fixed-strings 'SwiftTUIWebHost' Platforms/CLI/Sources Sources \
  --glob '*.swift' \
  | rg -v '^Sources/SwiftTUI/SwiftTUI\.swift:.*SwiftTUIWebHostCLI$' \
  | rg -v '^Sources/SwiftTUI/App\.swift:.*SwiftTUIWebHostCLI$'
then
  fail 'Only the SwiftTUI convenience target may reference SwiftTUIWebHostCLI outside Platforms/WebHost.'
fi

if rg -n --fixed-strings 'FlyingFox' Platforms/CLI/Sources Sources \
  --glob '*.swift'
then
  fail 'FlyingFox must only be referenced by the WebHost target.'
fi

swift_tui_target_block=$(target_block SwiftTUI)
swift_tui_runtime_target_block=$(target_block SwiftTUIRuntime)

case "$swift_tui_runtime_target_block" in
  *SwiftTUICLI*|*SwiftTUIWebHost*|*FlyingFox*|*UnixSignals*|*SwiftTerm*)
    fail 'The SwiftTUIRuntime target must not depend on host, terminal-runner, or terminal-emulator products.'
    ;;
esac

case "$swift_tui_target_block" in
  *SwiftTUIWebHostCLI*) ;;
  *) fail 'The SwiftTUI target should depend on SwiftTUIWebHostCLI.' ;;
esac

case "$swift_tui_target_block" in
  *SwiftTUIAnimatedImage*) ;;
  *) fail 'The SwiftTUI target should depend on SwiftTUIAnimatedImage.' ;;
esac

case "$swift_tui_target_block" in
  *SwiftTUIArguments*) ;;
  *) fail 'The SwiftTUI target should depend on SwiftTUIArguments.' ;;
esac

case "$swift_tui_target_block" in
  *SwiftTUIRuntime*) ;;
  *) fail 'The SwiftTUI target should depend on SwiftTUIRuntime.' ;;
esac

case "$swift_tui_target_block" in
  *'"SwiftTUICLI"'*)
    fail 'The SwiftTUI convenience target should inherit terminal launch through SwiftTUIWebHostCLI.'
    ;;
esac

case "$swift_tui_target_block" in
  *'"SwiftTUIWebHost"'*|*FlyingFox*)
    fail 'The SwiftTUI convenience target must not depend directly on SwiftTUIWebHost or FlyingFox.'
    ;;
esac

case "$swift_tui_target_block" in
  *SwiftTUICharts*)
    fail 'The SwiftTUI convenience target must not depend on SwiftTUICharts.'
    ;;
esac

arguments_target_block=$(target_block SwiftTUIArguments)

case "$arguments_target_block" in
  *SwiftTUIRuntime*) ;;
  *) fail 'The SwiftTUIArguments target should depend on SwiftTUIRuntime.' ;;
esac

case "$arguments_target_block" in
  *'"SwiftTUI"'*)
    fail 'The SwiftTUIArguments target must not depend on the SwiftTUI convenience product.'
    ;;
esac

cli_target_block=$(target_block SwiftTUICLI)

case "$cli_target_block" in
  *SwiftTUIWebHost*|*FlyingFox*)
    fail 'The SwiftTUICLI target must not depend on SwiftTUIWebHost or FlyingFox.'
    ;;
esac

case "$cli_target_block" in
  *SwiftTUIRuntime*) ;;
  *) fail 'The SwiftTUICLI target should depend on SwiftTUIRuntime.' ;;
esac

case "$cli_target_block" in
  *SwiftTUIArguments*) ;;
  *) fail 'The SwiftTUICLI target should depend on SwiftTUIArguments.' ;;
esac

case "$cli_target_block" in
  *'"SwiftTUI"'*)
    fail 'The SwiftTUICLI target must not depend on the SwiftTUI convenience product.'
    ;;
esac

for host_target in SwiftTUIWebHost SwiftTUIWASI WASISurfaceBridge SwiftUIHost SwiftTUITerminal SwiftTUITerminalWorkspace
do
  host_target_block=$(target_block "$host_target")

  case "$host_target_block" in
    *SwiftTUIRuntime*) ;;
    *) fail "The $host_target target should depend on SwiftTUIRuntime." ;;
  esac

  case "$host_target_block" in
    *'"SwiftTUI"'*|*SwiftTUICLI*)
      fail "The $host_target target must not depend on the SwiftTUI convenience or CLI products."
      ;;
  esac
done

webhost_target_block=$(target_block SwiftTUIWebHost)

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
