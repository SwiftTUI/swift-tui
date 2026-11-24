# shellcheck shell=bash
# Shared helpers for the Android cross-compile gate
# (Scripts/check_android_cross_compile.sh) and its provisioning script
# (Scripts/install_android_cross_compile_tools.sh). Sourced by bash after the
# caller sets `repo_root`; never executed.
#
# Every helper fails loudly. Nothing here skips: a missing toolchain, Swift SDK
# or NDK is a red verdict with the command that repairs it.

# shellcheck source=Scripts/lib/android_cross_compile_pins.sh
. "$repo_root/Scripts/lib/android_cross_compile_pins.sh"

# When set, android_fail also appends the error to this file, so the retained
# evidence carries the exact failure and not only the passing preamble.
android_error_log=""

android_note() {
  printf '[android-cross-compile] %s\n' "$*"
}

# android_fail <summary> [hint...]
# The summary is one line: it becomes the GitHub annotation. Hints follow on
# their own lines.
android_fail() {
  android_fail_summary=$1
  shift
  {
    printf '[android-cross-compile] error: %s\n' "$android_fail_summary"
    for android_fail_hint in "$@"; do
      printf '[android-cross-compile]   %s\n' "$android_fail_hint"
    done
  } >&2
  if [ -n "$android_error_log" ]; then
    {
      printf 'error: %s\n' "$android_fail_summary"
      for android_fail_hint in "$@"; do
        printf '  %s\n' "$android_fail_hint"
      done
    } >>"$android_error_log"
  fi
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    printf '::error::%s\n' "$android_fail_summary"
  fi
  exit 1
}

# Prints the first line of its stdin, reading all of it so the writer never
# takes a SIGPIPE under `set -o pipefail`.
android_first_line() {
  sed -n '1p'
}

# Sets `android_swift_version` from .swift-version and requires the pins to be
# the ones published for that toolchain.
android_require_pins_for_swift_version() {
  if [ ! -f "$repo_root/.swift-version" ]; then
    android_fail "no .swift-version at $repo_root; run this from a swift-tui checkout"
  fi
  android_swift_version="$(tr -d '[:space:]' <"$repo_root/.swift-version")"
  if ! printf '%s' "$android_swift_version" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    android_fail "unexpected .swift-version contents: '$android_swift_version'"
  fi
  if [ "$android_swift_version" != "$android_pin_swift_version" ]; then
    android_fail \
      ".swift-version pins Swift $android_swift_version but the Android pins are for Swift $android_pin_swift_version" \
      "Update the Swift SDK id, URL and checksum in Scripts/lib/android_cross_compile_pins.sh for the new toolchain."
  fi
}

# Requires swiftly and the toolchain .swift-version pins. Sets
# `android_toolchain_description` to the compiler's own first version line.
android_require_pinned_toolchain() {
  android_require_pins_for_swift_version
  if ! command -v swiftly >/dev/null 2>&1; then
    android_fail \
      "swiftly is not on PATH, so the pinned Swift $android_swift_version toolchain cannot be selected" \
      "Install swiftly (https://www.swift.org/install/), then run: swiftly install $android_swift_version"
  fi
  if ! android_toolchain_output="$(cd "$repo_root" && swiftly run swift --version 2>&1)"; then
    android_fail \
      "swiftly could not run the pinned Swift $android_swift_version toolchain: $(printf '%s\n' "$android_toolchain_output" | android_first_line)" \
      "Install it with: swiftly install $android_swift_version"
  fi
  android_toolchain_description="$(printf '%s\n' "$android_toolchain_output" | grep -E 'Swift version' | android_first_line || true)"
  # Swift may omit a zero patch component from its version banner.
  android_escaped_version="$(printf '%s' "${android_swift_version%.0}" | sed 's/\./\\./g')"
  if [ "$android_swift_version" != "${android_swift_version%.0}" ]; then
    android_escaped_version="${android_escaped_version}(\\.0)?"
  fi
  if ! printf '%s' "$android_toolchain_description" |
    grep -Eq "Swift version ${android_escaped_version}([^0-9.]|\$)"; then
    android_fail \
      "toolchain drift: .swift-version pins $android_swift_version but swiftly runs '${android_toolchain_description:-unknown}'" \
      "Install the pinned toolchain with: swiftly install $android_swift_version"
  fi
}

# `--swift-sdks-path` arguments for every `swift sdk` / `swift build` call.
# SWIFTTUI_SWIFT_SDKS_PATH points SwiftPM at a non-default Swift SDK directory;
# unset, SwiftPM uses its per-user default.
android_swift_sdks_path_args=()
if [ -n "${SWIFTTUI_SWIFT_SDKS_PATH:-}" ]; then
  android_swift_sdks_path_args=(--swift-sdks-path "$SWIFTTUI_SWIFT_SDKS_PATH")
fi

android_swift_sdks_path_description() {
  if [ -n "${SWIFTTUI_SWIFT_SDKS_PATH:-}" ]; then
    printf '%s\n' "$SWIFTTUI_SWIFT_SDKS_PATH"
  else
    printf "SwiftPM's default\n"
  fi
}

# Prints `swift sdk list`. `${array[@]+...}` is the bash 3.2-safe expansion of
# a possibly empty array under `set -u`.
android_swift_sdk_list() {
  (cd "$repo_root" &&
    swiftly run swift sdk list \
      ${android_swift_sdks_path_args[@]+"${android_swift_sdks_path_args[@]}"} 2>&1)
}

# True when the pinned Swift SDK for Android is installed. The id must be a
# whole line: a `swift-6.4.3-RELEASE_android-something` neighbour is not it.
android_swift_sdk_is_installed() {
  android_installed_sdks="$(android_swift_sdk_list)" || return 1
  printf '%s\n' "$android_installed_sdks" | grep -Fx -- "$android_swift_sdk_id" >/dev/null
}

android_swift_sdk_install_command() {
  printf 'swiftly run swift sdk install %s --checksum %s' \
    "$android_swift_sdk_url" "$android_swift_sdk_sha256"
}

# The NDK version the gate requires. SWIFTTUI_ANDROID_NDK_VERSION exists for
# diagnosis against another installed NDK; the gate records when it is used.
android_expected_ndk_version() {
  printf '%s\n' "${SWIFTTUI_ANDROID_NDK_VERSION:-$android_ndk_pinned_version}"
}

# The Android SDK directory, by the same precedence the Android Gradle tooling
# uses, falling back to Android Studio's per-platform default.
android_sdk_home() {
  if [ -n "${ANDROID_HOME:-}" ]; then
    printf '%s\n' "$ANDROID_HOME"
  elif [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
  elif [ "$(uname -s)" = "Darwin" ]; then
    printf '%s\n' "$HOME/Library/Android/sdk"
  else
    printf '%s\n' "$HOME/Android/Sdk"
  fi
}

# ANDROID_NDK_HOME is the variable the Swift SDK's own setup script reads, so
# it wins; otherwise the pinned version under the Android SDK directory.
android_ndk_home() {
  if [ -n "${ANDROID_NDK_HOME:-}" ]; then
    printf '%s\n' "$ANDROID_NDK_HOME"
  else
    printf '%s/ndk/%s\n' "$(android_sdk_home)" "$(android_expected_ndk_version)"
  fi
}

# Prints Pkg.Revision from an NDK's source.properties, or nothing.
android_ndk_revision() {
  if [ -f "$1/source.properties" ]; then
    sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*//p' "$1/source.properties" |
      android_first_line | tr -d '[:space:]'
  fi
}

android_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    android_fail "neither sha256sum nor shasum is available to verify $1"
  fi
}
