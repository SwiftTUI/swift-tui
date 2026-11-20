#!/usr/bin/env bash
# Build the external transition consumer against this checkout (STUI-1543).
#
# Scripts/data/transition-consumer is a SwiftPM package a third party could
# have written: its library target depends on the SwiftTUIViews product alone,
# uses the Swift settings of the SwiftTUI library repositories, declares its
# own Transition types and uses every public symbol of the transition surface.
# Building it proves the surface is complete and usable from outside the
# package.
#
# The package is copied out of the tree first, so each run starts from fresh
# consumer state and leaves no build products or resolved file beside the
# fixture. Failed state is kept for diagnosis.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
fixture="${repo_root}/Scripts/data/transition-consumer"
scratch_root="${repo_root}/.build/transition-consumer"
mkdir -p "${scratch_root}"
scratch="$(mktemp -d "${scratch_root}/run.XXXXXX")"
cleanup() {
  result=$?
  if [ "$result" -eq 0 ]; then
    rm -rf "${scratch}"
  else
    echo "[check_transition_consumer] Failed consumer state retained: ${scratch}" >&2
  fi
  exit "$result"
}
trap cleanup EXIT
echo "[check_transition_consumer] Fresh consumer state: ${scratch}"

# The copy sits three directories below the checkout, as the fixture does, so
# the manifest's literal "../../.." package path reaches this checkout.
consumer="${scratch}"
cp "${fixture}/Package.swift" "${consumer}/Package.swift"
cp -R "${fixture}/Sources" "${consumer}/Sources"
if [ -d "${fixture}/Tests" ]; then
  cp -R "${fixture}/Tests" "${consumer}/Tests"
fi

echo "[check_transition_consumer] Building the SwiftTUIViews-only transition consumer"
# The copy depends on this checkout by path and never on a published release.
swiftly run swift build \
  --package-path "${consumer}" --jobs "${SWIFTTUI_PUBLIC_API_SWIFT_JOBS:-4}"
echo "[check_transition_consumer] ok"
