#!/usr/bin/env bash

# Prepares a GitHub Actions `container:` job that runs in the prebuilt
# ghcr.io/swifttui/swift-tui-linux image (Scripts/linux/Dockerfile) for the
# repo gate's lanes (.github/workflows/run-tests-linux.yml).
#
# The runner overrides HOME to /github/home inside the container, while the
# image installed swiftly under /root/.local/share/swiftly, bun under
# /usr/local/bun, and the wasm Swift SDK under /root/.swiftpm/swift-sdks
# (SwiftPM looks for SDKs under $HOME/.swiftpm). This script bridges the two:
# it puts the toolchain and bun on $GITHUB_PATH for every later step, links the
# image's SDK directory into the runner's HOME, and then asserts the image's
# toolchain is exactly the version .swift-version pins — the image/toolchain
# drift guard of plan 2026-08-25-001 §9. It fails loud rather than installing
# anything: a mismatch means the workflow's image tag was not bumped with the
# toolchain pin.

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

swiftly_home="${SWIFTLY_HOME_DIR:-/root/.local/share/swiftly}"
swiftly_bin="${SWIFTLY_BIN_DIR:-/root/.local/bin}"
bun_bin="${BUN_INSTALL:-/usr/local/bun}/bin"

if [ ! -f "$swiftly_home/env.sh" ]; then
  echo "::error::no swiftly environment at $swiftly_home/env.sh — is this job running in the swift-tui-linux image?"
  exit 1
fi

# shellcheck disable=SC1091
. "$swiftly_home/env.sh"
export PATH="$swiftly_bin:$bun_bin:$PATH"
hash -r

if [ "${HOME:-/root}" != "/root" ] && [ -d /root/.swiftpm/swift-sdks ]; then
  mkdir -p "$HOME/.swiftpm"
  if [ ! -e "$HOME/.swiftpm/swift-sdks" ]; then
    ln -s /root/.swiftpm/swift-sdks "$HOME/.swiftpm/swift-sdks"
  fi
fi

expected="$(tr -d '[:space:]' < .swift-version)"
if ! printf '%s' "$expected" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
  echo "::error::unexpected .swift-version contents: '$expected'"
  exit 1
fi
actual="$(swiftly run swift --version 2>&1 | head -n 1)"
escaped="$(printf '%s' "$expected" | sed 's/\./\\./g')"
if ! printf '%s' "$actual" | grep -Eq "Swift version ${escaped}([^0-9.]|$)"; then
  echo "::error::toolchain drift: .swift-version pins ${expected} but the container image runs '${actual}'. Bump the image tag in the workflow together with .swift-version (build-linux-image.yml publishes swift-<version> tags)."
  exit 1
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  printf '%s\n%s\n' "$swiftly_bin" "$bun_bin" >> "$GITHUB_PATH"
fi
if [ -n "${GITHUB_ENV:-}" ]; then
  printf 'SWIFTLY_HOME_DIR=%s\nSWIFTLY_BIN_DIR=%s\n' "$swiftly_home" "$swiftly_bin" >> "$GITHUB_ENV"
fi

echo "toolchain: $actual"
echo "bun: $(bun --version)"
echo "HOME: ${HOME:-unset}"
