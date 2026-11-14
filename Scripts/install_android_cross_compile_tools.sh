#!/usr/bin/env bash

# Provisions what Scripts/check_android_cross_compile.sh requires on a clean
# Linux host — the Repo Gate's `android-cross-compile` job, or a container:
#
#   * the Swift SDK for Android published for the toolchain .swift-version pins
#   * the pinned Android NDK, from Google's Linux archive
#
# Both are pinned by URL and SHA-256 in Scripts/lib/android_cross_compile_pins.sh.
# The Swift toolchain itself is not installed here: the swift-tui-linux image
# (or swiftly) owns it, and this script fails when it is not the pinned one.
#
# The script is idempotent and never replaces a tool: an installed Swift SDK or
# an NDK of the right version is left alone, and an NDK of another version at
# the target path is an error. It does not run the SDK's setup-android-sdk.sh;
# the gate materializes the sysroot and records that in its evidence.
#
# Downloaded archives stay in SWIFTTUI_ANDROID_ARCHIVE_DIR so CI can cache
# them. An archive found there is verified against its pinned checksum before
# it is used, exactly like a fresh download, so a stale or tampered cache
# cannot change what gets installed.
#
# Knobs (env, all optional):
#   SWIFTTUI_ANDROID_ARCHIVE_DIR   download directory
#                                  (default: ~/.cache/swifttui-android-archives)
#   SWIFTTUI_SWIFT_SDKS_PATH       install the Swift SDK into a non-default
#                                  SwiftPM Swift SDK directory
#   ANDROID_NDK_HOME               where the NDK goes (default: the pinned
#                                  version under ANDROID_HOME / ANDROID_SDK_ROOT
#                                  / ~/Android/Sdk)
#   SWIFTTUI_ANDROID_LOG_DIR       evidence directory shared with the gate
#
# On macOS the Swift SDK is installed the same way; install the NDK with the
# Android SDK manager (`sdkmanager --install 'ndk;<version>'`).

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# shellcheck source=Scripts/lib/android_cross_compile.sh
. "$repo_root/Scripts/lib/android_cross_compile.sh"

usage() {
  cat <<EOF
Usage: Scripts/install_android_cross_compile_tools.sh

Installs the $android_swift_sdk_id Swift SDK and, on Linux, Android NDK
$android_ndk_pinned_version for Scripts/check_android_cross_compile.sh. Both
are verified against the SHA-256 pinned in
Scripts/lib/android_cross_compile_pins.sh. Tools already present are left alone.
EOF
}

if [ "$#" -ne 0 ]; then
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf >&2 'Unknown argument: %s\n\n' "$1"
    usage >&2
    exit 2
    ;;
  esac
fi

archive_dir="${SWIFTTUI_ANDROID_ARCHIVE_DIR:-$HOME/.cache/swifttui-android-archives}"
log_dir="${SWIFTTUI_ANDROID_LOG_DIR:-$repo_root/.build/android-cross-compile}"

# fetch_archive <url> <sha256> <destination>
# Leaves a verified archive at <destination>, downloading it unless a verified
# copy is already there. Every network call is bounded: a mirror that stalls
# mid-transfer aborts after a minute below 10 KiB/s and is retried.
fetch_archive() {
  fa_url=$1
  fa_sha256=$2
  fa_destination=$3

  if [ -f "$fa_destination" ]; then
    fa_actual="$(android_sha256 "$fa_destination")"
    if [ "$fa_actual" = "$fa_sha256" ]; then
      android_note "using the verified archive already at $fa_destination"
      return 0
    fi
    android_note "discarding $fa_destination: SHA-256 $fa_actual is not the pinned $fa_sha256"
    rm -f "$fa_destination"
  fi

  if ! command -v curl >/dev/null 2>&1; then
    android_fail "curl is required to download $fa_url"
  fi
  android_note "downloading $fa_url"
  rm -f "$fa_destination.partial"
  if ! curl --fail --location --silent --show-error \
    --connect-timeout 30 --retry 3 --retry-delay 5 \
    --speed-limit 10240 --speed-time 60 --max-time 1800 \
    --output "$fa_destination.partial" "$fa_url"; then
    rm -f "$fa_destination.partial"
    android_fail "could not download $fa_url"
  fi
  fa_actual="$(android_sha256 "$fa_destination.partial")"
  if [ "$fa_actual" != "$fa_sha256" ]; then
    rm -f "$fa_destination.partial"
    android_fail \
      "checksum mismatch for $fa_url: expected SHA-256 $fa_sha256, got $fa_actual" \
      "If the publisher replaced the archive, review it and update Scripts/lib/android_cross_compile_pins.sh."
  fi
  mv "$fa_destination.partial" "$fa_destination"
  android_note "verified SHA-256 $fa_actual"
}

install_swift_sdk() {
  if android_swift_sdk_is_installed; then
    android_note "Swift SDK $android_swift_sdk_id is already installed ($(android_swift_sdks_path_description) Swift SDK directory)"
    return 0
  fi
  sdk_archive="$archive_dir/$(basename "$android_swift_sdk_url")"
  fetch_archive "$android_swift_sdk_url" "$android_swift_sdk_sha256" "$sdk_archive"
  android_note "installing Swift SDK $android_swift_sdk_id"
  swiftly run swift sdk install \
    ${android_swift_sdks_path_args[@]+"${android_swift_sdks_path_args[@]}"} \
    "$sdk_archive" --checksum "$android_swift_sdk_sha256"
  if ! android_swift_sdk_is_installed; then
    android_fail "swift sdk install finished but '$android_swift_sdk_id' is not in swift sdk list"
  fi
}

install_ndk() {
  ndk_version="$(android_expected_ndk_version)"
  ndk_home="$(android_ndk_home)"
  if [ "$ndk_version" != "$android_ndk_pinned_version" ]; then
    android_fail \
      "SWIFTTUI_ANDROID_NDK_VERSION=$ndk_version is not the pinned NDK $android_ndk_pinned_version" \
      "This script installs only the pinned NDK; it has no checksum for another."
  fi

  if [ -e "$ndk_home" ]; then
    installed_revision="$(android_ndk_revision "$ndk_home")"
    if [ "$installed_revision" = "$ndk_version" ]; then
      android_note "Android NDK $ndk_version is already installed at $ndk_home"
      return 0
    fi
    android_fail \
      "$ndk_home exists but is ${installed_revision:+NDK }${installed_revision:-not an NDK}, not NDK $ndk_version" \
      "Remove it, or point ANDROID_NDK_HOME at the directory NDK $ndk_version should be installed to."
  fi

  if [ "$(uname -s)" != "Linux" ]; then
    android_fail \
      "Android NDK $ndk_version not found at $ndk_home, and this script downloads only Google's Linux archive" \
      "Install it with the Android SDK manager: sdkmanager --install 'ndk;$ndk_version'"
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    android_fail "unzip is required to unpack the Android NDK archive"
  fi

  ndk_archive="$archive_dir/$(basename "$android_ndk_linux_url")"
  fetch_archive "$android_ndk_linux_url" "$android_ndk_linux_sha256" "$ndk_archive"

  # Unpack next to the destination so the final step is a rename, never a
  # half-populated NDK at the path the gate reads.
  ndk_parent="$(dirname "$ndk_home")"
  mkdir -p "$ndk_parent"
  ndk_staging="$(mktemp -d "$ndk_parent/.ndk-unpack.XXXXXX")"
  android_note "unpacking the Android NDK into $ndk_home"
  if ! unzip -q "$ndk_archive" -d "$ndk_staging"; then
    rm -rf "$ndk_staging"
    android_fail "could not unpack $ndk_archive"
  fi
  ndk_unpacked=""
  for candidate in "$ndk_staging"/*; do
    if [ -f "$candidate/source.properties" ]; then
      ndk_unpacked=$candidate
      break
    fi
  done
  unpacked_revision="$(android_ndk_revision "${ndk_unpacked:-$ndk_staging}")"
  if [ -z "$ndk_unpacked" ] || [ "$unpacked_revision" != "$ndk_version" ]; then
    rm -rf "$ndk_staging"
    android_fail "$ndk_archive unpacked to NDK '${unpacked_revision:-unknown}', not $ndk_version"
  fi
  mv "$ndk_unpacked" "$ndk_home"
  rm -rf "$ndk_staging"
}

main() {
  android_note "provisioning the Android cross-compile tools"
  android_require_pinned_toolchain
  android_note "toolchain: $android_toolchain_description"
  mkdir -p "$archive_dir"
  android_note "archive directory: $archive_dir"

  install_swift_sdk
  install_ndk

  # Later workflow steps resolve the same NDK without re-deriving the path.
  if [ -n "${GITHUB_ENV:-}" ]; then
    printf 'ANDROID_NDK_HOME=%s\n' "$ndk_home" >>"$GITHUB_ENV"
  fi

  android_note "Swift SDK: $android_swift_sdk_id ($(android_swift_sdks_path_description) Swift SDK directory)"
  android_note "Android NDK: $(android_ndk_revision "$ndk_home") at $ndk_home"
  android_note "OK: run Scripts/check_android_cross_compile.sh"
}

mkdir -p "$log_dir"
main 2>&1 | tee "$log_dir/install.log"
