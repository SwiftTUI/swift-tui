#!/usr/bin/env bash

# Cross-compiles the Android host — the SwiftTUIAndroidHost target and its
# whole dependency closure — for Android, with the pinned Swift toolchain, the
# matching Swift SDK for Android and the pinned Android NDK.
#
# The Linux and macOS lanes never build `#if os(Android)` code, so an
# Android-only break is invisible to them. This is the compile contract for
# that code. It runs in the Repo Gate's `android-cross-compile` job
# (.github/workflows/run-tests-linux.yml) and from a fresh clone on any host
# that has the three tools:
#
#   Scripts/check_android_cross_compile.sh
#   Scripts/check_android_cross_compile.sh --triple aarch64-unknown-linux-android28
#   Scripts/check_android_cross_compile.sh --triple aarch64-unknown-linux-android28 --build-system native
#
# Missing tooling is a failure, never a skip. The script installs nothing;
# Scripts/install_android_cross_compile_tools.sh provisions a clean Linux host.
#
# `--target`, not `--product`: with SwiftPM's native build engine a library
# product build compiles the whole package graph, which includes targets that
# deliberately do not build for Android (the vendored UnixSignals crash
# handler). The target build is exactly the SwiftTUIAndroidHost closure on
# either engine. Linking, APK packaging and running on a device are outside
# this gate.
#
# Two build engines, because they reach the NDK differently:
#
#   * default — whatever `swift build` selects on the pinned toolchain (Swift
#     Build on 6.4). It takes the sysroot, the compiler's builtin headers and
#     the per-module linker straight from the NDK it finds through
#     ANDROID_NDK_HOME, so the gate exports the pinned NDK to it. The NDK's
#     linker has to run on the build host; Google publishes Linux host tools
#     for x86_64 only.
#   * native — SwiftPM's own engine, which is how the `sh.swifttui.android`
#     Gradle plugin builds an app's Swift code. It reads the Swift SDK's
#     ndk-sysroot, which the bundle's setup-android-sdk.sh links to the NDK.
#     Without that link the first Swift module fails on
#     "'semaphore.h' file not found" (SwiftOverlayShims).
#
# The one thing the script writes outside the checkout is that ndk-sysroot,
# and only through the bundle's own setup script:
#
#   * a freshly installed SDK has no ndk-sysroot, so it is materialized;
#   * an ndk-sysroot that already exists is verified against the pinned NDK and
#     left alone. If its headers are another NDK's the gate fails, unless
#     SWIFTTUI_ANDROID_RELINK_SYSROOT=1 asks for a relink. The relink replaces
#     the sysroot of a Swift SDK that other Android builds may be using.
#
# Evidence is written to .build/android-cross-compile (override with
# SWIFTTUI_ANDROID_LOG_DIR): environment.txt for the latest run (it also holds
# the error when the run stops before compiling), sysroot-setup.log when the
# sysroot was materialized, and per step a build-<triple>-<engine>.log that
# opens with that environment and a one-line verdict-<triple>-<engine>.txt.
#
# Knobs (env, all optional):
#   ANDROID_NDK_HOME                the NDK to use (default: the pinned version
#                                   under ANDROID_HOME / ANDROID_SDK_ROOT / the
#                                   Android Studio default SDK directory)
#   SWIFTTUI_SWIFT_SDKS_PATH        a non-default SwiftPM Swift SDK directory
#   SWIFTTUI_ANDROID_SCRATCH_PATH   SwiftPM scratch path (default: .build)
#   SWIFTTUI_ANDROID_LOG_DIR        evidence directory
#   SWIFTTUI_ANDROID_RELINK_SYSROOT 1 relinks an ndk-sysroot that points at
#                                   another NDK
#   SWIFTTUI_ANDROID_NDK_VERSION    require another NDK version (diagnosis)
#   SWIFTTUI_ANDROID_STEP_TIMEOUT_SECONDS
#                                   silence bound per compile (default 300;
#                                   0 disables the watchdog)
#   SWIFTTUI_WARNINGS_AS_ERRORS     defaults to 1 here, as in the repo gate

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# shellcheck source=Scripts/lib/android_cross_compile.sh
. "$repo_root/Scripts/lib/android_cross_compile.sh"

read -r -a default_steps <<<"$android_default_steps"

usage() {
  cat <<EOF
Usage: Scripts/check_android_cross_compile.sh
       Scripts/check_android_cross_compile.sh --triple <triple>... [--build-system default|native]

Cross-compiles the $android_host_target target for Android and fails when the
pinned Swift toolchain, the $android_swift_sdk_id Swift SDK, or Android NDK
$android_ndk_pinned_version is missing, or when the compile fails.

Without arguments, every step of the gate runs (<triple>:<build engine>):
$(printf '  %s\n' "${default_steps[@]}")

--build-system default uses the engine \`swift build\` selects on the pinned
toolchain; native uses SwiftPM's own engine, as the Android Gradle plugin does.

Provision a clean Linux host with Scripts/install_android_cross_compile_tools.sh.
EOF
}

usage_error() {
  printf >&2 '%s\n\n' "$1"
  usage >&2
  exit 2
}

triples=()
engine=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  --triple)
    [ "$#" -ge 2 ] || usage_error "--triple needs a value"
    triples+=("$2")
    shift 2
    ;;
  --triple=*)
    triples+=("${1#--triple=}")
    shift
    ;;
  --build-system)
    [ "$#" -ge 2 ] || usage_error "--build-system needs a value"
    engine=$2
    shift 2
    ;;
  --build-system=*)
    engine=${1#--build-system=}
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage_error "Unknown argument: $1"
    ;;
  esac
done

# The ELF e_machine each architecture must produce, checked after the build.
elf_machine_for_triple() {
  case "$1" in
  aarch64-unknown-linux-android[0-9]*) printf '183\n' ;;
  x86_64-unknown-linux-android[0-9]*) printf '62\n' ;;
  armv7-unknown-linux-android[0-9]*) printf '40\n' ;;
  *) return 1 ;;
  esac
}

steps=()
if [ "${#triples[@]}" -eq 0 ]; then
  [ -z "$engine" ] || usage_error "--build-system needs at least one --triple"
  steps=("${default_steps[@]}")
else
  for triple in "${triples[@]}"; do
    steps+=("$triple:${engine:-default}")
  done
fi
for step in "${steps[@]}"; do
  elf_machine_for_triple "${step%%:*}" >/dev/null ||
    usage_error "Unsupported Android triple: ${step%%:*}"
  case "${step##*:}" in
  default | native) ;;
  *) usage_error "Unsupported build system: ${step##*:}" ;;
  esac
done

export SWIFTTUI_WARNINGS_AS_ERRORS="${SWIFTTUI_WARNINGS_AS_ERRORS:-1}"

# The repo gate's step watchdog: a compile prints continuously, so one that is
# silent and idle for the bound is wedged. It is dumped and killed here, with
# a TIMEOUT line in its log, instead of costing the job its whole cap.
# Worst-case kill = 300 idle + 120 busy grace + 10 kill grace = 430 s.
step_timeout_seconds="${SWIFTTUI_ANDROID_STEP_TIMEOUT_SECONDS:-300}"
step_timeout_kill_grace_seconds=10
step_absolute_timeout_seconds=900
step_output_probe_ticks=25
step_busy_grace_seconds=120
step_busy_min_cpu_percent=25
# The android-cross-compile job's timeout-minutes, in seconds.
step_watchdog_deadline_seconds=1800
# shellcheck source=Scripts/lib/step_watchdog.sh
. "$repo_root/Scripts/lib/step_watchdog.sh"
validate_timeout_configuration

log_dir="${SWIFTTUI_ANDROID_LOG_DIR:-$repo_root/.build/android-cross-compile}"
mkdir -p "$log_dir"
environment_file="$log_dir/environment.txt"
: >"$environment_file"
android_error_log="$environment_file"

# Evidence lines go to the console and to the retained environment file.
evidence() {
  printf '%s\n' "$*" | tee -a "$environment_file"
}

evidence "# Android cross-compile gate: environment"
evidence "date_utc: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
evidence "host: $(uname -srm)"
if [ -r /etc/os-release ]; then
  evidence "os: $(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"')"
elif command -v sw_vers >/dev/null 2>&1; then
  evidence "os: $(sw_vers -productName) $(sw_vers -productVersion)"
fi
if revision="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null)"; then
  if [ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null)" ]; then
    revision="$revision (with uncommitted changes)"
  fi
  evidence "revision: $revision"
else
  evidence "revision: unknown (not a git checkout)"
fi
evidence "target: $android_host_target"
evidence "steps: ${steps[*]}"
for variable in ANDROID_HOME ANDROID_SDK_ROOT ANDROID_NDK_HOME ANDROID_NDK_ROOT \
  DISABLE_EXPLICIT_PLATFORMS SWIFTTUI_WARNINGS_AS_ERRORS SWIFTTUI_SWIFT_SDKS_PATH \
  SWIFTTUI_ANDROID_SCRATCH_PATH; do
  evidence "inherited env $variable=${!variable-<unset>}"
done

# --- 1. the pinned toolchain --------------------------------------------------
android_require_pinned_toolchain
evidence "swift_version_pin: $android_swift_version"
evidence "swiftly: $(swiftly --version 2>&1 | android_first_line)"
evidence "toolchain: $android_toolchain_description"

# --- 2. the Swift SDK for Android ---------------------------------------------
evidence "swift_sdk_id: $android_swift_sdk_id"
evidence "swift_sdks_path: $(android_swift_sdks_path_description)"
if ! android_swift_sdk_is_installed; then
  evidence "swift sdk list:"
  evidence "${android_installed_sdks:-<no output>}"
  android_fail \
    "the Swift SDK for Android '$android_swift_sdk_id' is not installed ($(android_swift_sdks_path_description) Swift SDK directory)" \
    "Install it with: $(android_swift_sdk_install_command)" \
    "or provision a clean Linux host with Scripts/install_android_cross_compile_tools.sh"
fi
evidence "swift sdk list: $(printf '%s\n' "$android_installed_sdks" | tr '\n' ' ')"

# --- 3. the Android NDK -------------------------------------------------------
expected_ndk_version="$(android_expected_ndk_version)"
if [ "$expected_ndk_version" != "$android_ndk_pinned_version" ]; then
  evidence "ndk_version_override: SWIFTTUI_ANDROID_NDK_VERSION=$expected_ndk_version (the pin is $android_ndk_pinned_version)"
fi
ndk_home="$(android_ndk_home)"
evidence "ndk_home: $ndk_home"
if [ ! -d "$ndk_home/toolchains/llvm/prebuilt" ] || [ ! -f "$ndk_home/source.properties" ]; then
  android_fail \
    "Android NDK $expected_ndk_version not found at $ndk_home" \
    "Install it with the Android SDK manager: sdkmanager --install 'ndk;$expected_ndk_version'" \
    "or point ANDROID_NDK_HOME at an existing NDK $expected_ndk_version;" \
    "on a clean Linux host, Scripts/install_android_cross_compile_tools.sh downloads it."
fi
ndk_revision="$(android_ndk_revision "$ndk_home")"
evidence "ndk_revision: ${ndk_revision:-unknown}"
if [ "$ndk_revision" != "$expected_ndk_version" ]; then
  android_fail \
    "the NDK at $ndk_home is ${ndk_revision:-of unknown version}, but the gate requires $expected_ndk_version" \
    "Point ANDROID_NDK_HOME at NDK $expected_ndk_version (sdkmanager --install 'ndk;$expected_ndk_version')."
fi
ndk_real="$(cd -P "$ndk_home" && pwd -P)"

# The default engine takes its NDK from the environment and otherwise picks
# one from the Android SDK directory itself (30 on a machine that had 27.3 and
# 30). Pin it, under both names it and the Android tooling read, so every
# engine compiles against the same NDK.
export ANDROID_NDK_HOME="$ndk_home" ANDROID_NDK_ROOT="$ndk_home"
evidence "build env: ANDROID_NDK_HOME=$ANDROID_NDK_HOME ANDROID_NDK_ROOT=$ANDROID_NDK_ROOT"

# --- 4. the SDK's ndk-sysroot -------------------------------------------------
# The bundle's swift-sdk.json names its sysroot; ask SwiftPM where it is rather
# than guessing the per-platform Swift SDK directory.
first_triple="${steps[0]%%:*}"
if ! sdk_configuration="$(swiftly run swift sdk configure \
  ${android_swift_sdks_path_args[@]+"${android_swift_sdks_path_args[@]}"} \
  "$android_swift_sdk_id" "$first_triple" --show-configuration 2>&1)"; then
  evidence "$sdk_configuration"
  android_fail "swift sdk configure --show-configuration failed for $android_swift_sdk_id / $first_triple"
fi
sdk_root_path="$(printf '%s\n' "$sdk_configuration" | sed -n 's/^sdkRootPath:[[:space:]]*//p' | android_first_line)"
if [ -z "$sdk_root_path" ]; then
  evidence "$sdk_configuration"
  android_fail "could not read sdkRootPath for $android_swift_sdk_id from swift sdk configure --show-configuration"
fi
swift_android_root="$(dirname "$sdk_root_path")"
setup_script="$swift_android_root/scripts/setup-android-sdk.sh"
clang_resource_link="$swift_android_root/swift-resources/usr/lib/swift/clang"
evidence "swift_sdk_sysroot: $sdk_root_path"

ndk_version_of_headers() {
  awk '
    $1 == "#define" && $2 == "__NDK_MAJOR__" { major = $3 }
    $1 == "#define" && $2 == "__NDK_MINOR__" { minor = $3 }
    $1 == "#define" && $2 == "__NDK_BUILD__" { build = $3 }
    END { if (major != "" && minor != "" && build != "") print major "." minor "." build }
  ' "$1"
}

# Prints what is wrong with the materialized sysroot, or nothing. The header
# check reads the NDK's own version header, so it holds whether the setup
# script linked the NDK (the default) or copied it.
sysroot_problem() {
  version_header="$sdk_root_path/usr/include/android/ndk-version.h"
  if [ ! -f "$version_header" ]; then
    printf 'its usr/include does not resolve to NDK headers (%s is missing)\n' "$version_header"
    return
  fi
  sysroot_ndk_version="$(ndk_version_of_headers "$version_header")"
  if [ "$sysroot_ndk_version" != "$expected_ndk_version" ]; then
    printf 'its headers are NDK %s, not %s\n' "${sysroot_ndk_version:-of unknown version}" "$expected_ndk_version"
    return
  fi
  # LibcOverlayShims includes <semaphore.h>: the header whose absence is the
  # native engine's failure on an unlinked sysroot.
  if [ ! -f "$sdk_root_path/usr/include/semaphore.h" ]; then
    printf 'it has no usr/include/semaphore.h\n'
    return
  fi
  if [ ! -f "$clang_resource_link/include/stddef.h" ]; then
    printf 'the clang resource directory %s does not resolve\n' "$clang_resource_link"
    return
  fi
}

# Prints a drift that does not stop the compile, or nothing: the compiler's
# builtin headers linked from another NDK than the sysroot. Re-running the
# bundle's setup script against a second NDK leaves exactly this behind.
sysroot_drift() {
  [ -f "$clang_resource_link/include/stddef.h" ] || return 0
  clang_resource_real="$(cd -P "$clang_resource_link" && pwd -P)"
  case "$clang_resource_real" in
  "$ndk_real"/*) ;;
  *)
    printf 'the clang resource directory resolves to %s, outside the NDK at %s\n' \
      "$clang_resource_real" "$ndk_real"
    ;;
  esac
}

materialize_sysroot() {
  if [ ! -f "$setup_script" ]; then
    android_fail "the Swift SDK bundle has no setup script at $setup_script"
  fi
  # setup-android-sdk.sh replaces ndk-sysroot but links the clang resource
  # directory with `ln -sf`, which follows an existing link and writes into the
  # NDK it points at. Drop the stale link first.
  if [ -L "$clang_resource_link" ]; then
    rm -f "$clang_resource_link"
  fi
  android_note "materializing the sysroot: ANDROID_NDK_HOME=$ndk_home $setup_script"
  setup_status=0
  bash "$setup_script" >"$log_dir/sysroot-setup.log" 2>&1 || setup_status=$?
  cat "$log_dir/sysroot-setup.log"
  if [ "$setup_status" -ne 0 ]; then
    evidence "sysroot_setup: failed (exit $setup_status)"
    evidence "$(cat "$log_dir/sysroot-setup.log")"
    android_fail "setup-android-sdk.sh exited $setup_status (log: $log_dir/sysroot-setup.log)"
  fi
}

relink_command="SWIFTTUI_ANDROID_RELINK_SYSROOT=1 Scripts/check_android_cross_compile.sh"
relink_caution="The relink replaces this Swift SDK's ndk-sysroot; run it when no other Android build is using the SDK."
if [ ! -e "$sdk_root_path" ] && [ ! -L "$sdk_root_path" ]; then
  evidence "sysroot_setup: materialized (fresh Swift SDK install)"
  materialize_sysroot
else
  problem="$(sysroot_problem)"
  drift="$(sysroot_drift)"
  if [ -z "$problem$drift" ]; then
    evidence "sysroot_setup: already materialized for NDK $expected_ndk_version"
  elif [ "${SWIFTTUI_ANDROID_RELINK_SYSROOT:-0}" = "1" ]; then
    evidence "sysroot_setup: relinked (SWIFTTUI_ANDROID_RELINK_SYSROOT=1) because ${problem:-$drift}"
    materialize_sysroot
  elif [ -n "$problem" ]; then
    android_fail \
      "the Swift SDK sysroot at $sdk_root_path does not match NDK $expected_ndk_version: $problem" \
      "It was set up against another NDK. Relink it to $ndk_home with:" \
      "  $relink_command" \
      "$relink_caution"
  else
    evidence "sysroot_setup: already materialized for NDK $expected_ndk_version"
  fi
fi
problem="$(sysroot_problem)"
if [ -n "$problem" ]; then
  android_fail "the Swift SDK sysroot at $sdk_root_path is unusable after setup: $problem"
fi
evidence "sysroot_ndk_version: $(ndk_version_of_headers "$sdk_root_path/usr/include/android/ndk-version.h")"
evidence "sysroot_include: $(cd -P "$sdk_root_path/usr/include" && pwd -P)"
evidence "sysroot_semaphore_h: present"
evidence "clang_resource_dir: $(cd -P "$clang_resource_link" && pwd -P)"
drift="$(sysroot_drift)"
if [ -n "$drift" ]; then
  evidence "warning: $drift"
  android_note "warning: the native build engine reads the compiler's builtin headers through that link, so it uses another NDK's; CI links both from NDK $expected_ndk_version."
  android_note "  Relink with: $relink_command"
  android_note "  $relink_caution"
fi

# --- 5. the cross-compile, one step per triple and engine ---------------------
# The default engine links each module with the NDK's own ld.lld. Prints why
# that cannot work on this host, or nothing.
ndk_linker_problem() {
  for nlp_linker in "$ndk_home"/toolchains/llvm/prebuilt/*/bin/ld.lld; do
    if [ -x "$nlp_linker" ] && "$nlp_linker" --version >/dev/null 2>&1; then
      return 0
    fi
  done
  printf 'the NDK linker (%s/toolchains/llvm/prebuilt/*/bin/ld.lld) cannot run on this %s host, and the default build engine links every module with it; Google publishes Linux NDK host tools for x86_64 only — use --build-system native here\n' \
    "$ndk_home" "$(uname -sm)"
}

# A build that reports success must have produced Android objects for this
# architecture. This rejects a build that compiled nothing, or compiled for the
# host, without depending on either build engine's directory layout.
verify_objects() {
  vo_triple=$1
  vo_log=$2
  vo_expected_machine="$(elf_machine_for_triple "$vo_triple")"
  if ! vo_bin_path="$(swiftly run swift "${build_command[@]}" --show-bin-path 2>>"$vo_log" | tail -n 1)" ||
    [ ! -d "$vo_bin_path" ]; then
    printf 'no product directory for %s (--show-bin-path: %s)\n' "$vo_triple" "${vo_bin_path:-<none>}"
    return 1
  fi
  vo_checked=0
  while IFS= read -r vo_object; do
    [ -n "$vo_object" ] || continue
    vo_magic="$(od -An -tx1 -N4 "$vo_object" | tr -d ' \n')"
    # BSD od ends its output with a blank line; read the first data line only.
    vo_machine="$(od -An -tu1 -j18 -N2 "$vo_object" | awk 'NF { print $1 + $2 * 256; exit }')"
    if [ "$vo_magic" != "7f454c46" ] || [ "$vo_machine" != "$vo_expected_machine" ]; then
      printf '%s is not an ELF object for %s (magic %s, e_machine %s, expected %s)\n' \
        "$vo_object" "$vo_triple" "$vo_magic" "$vo_machine" "$vo_expected_machine"
      return 1
    fi
    vo_checked=$((vo_checked + 1))
  done <<EOF
$(find "$vo_bin_path" -type f -name '*.o' -path "*${android_host_target}*" 2>/dev/null)
EOF
  if [ "$vo_checked" -eq 0 ]; then
    printf 'the build reported success but left no %s object under %s\n' \
      "$android_host_target" "$vo_bin_path"
    return 1
  fi
  printf '%s %s object(s) under %s are ELF e_machine %s\n' \
    "$vo_checked" "$android_host_target" "$vo_bin_path" "$vo_expected_machine"
}

failed_steps=()
step_number=0
for step in "${steps[@]}"; do
  step_number=$((step_number + 1))
  triple="${step%%:*}"
  step_engine="${step##*:}"
  label="$triple-$step_engine"
  build_log="$log_dir/build-$label.log"
  raw_log="$log_dir/build-$label.raw.log"
  status_file="$log_dir/build-$label.status"
  timeout_file="$log_dir/build-$label.timeout"
  verdict_file="$log_dir/verdict-$label.txt"

  # Both engines build into SwiftPM's default scratch path unless one is
  # given: they keep their products apart there, and a longer path makes the
  # native engine's per-module compiler messages longer for no benefit.
  build_command=(build --swift-sdk "$android_swift_sdk_id" --triple "$triple"
    --target "$android_host_target")
  if [ "$step_engine" = "native" ]; then
    build_command+=(--build-system native)
  fi
  if [ -n "${SWIFTTUI_ANDROID_SCRATCH_PATH:-}" ]; then
    build_command+=(--scratch-path "$SWIFTTUI_ANDROID_SCRATCH_PATH")
  fi
  if [ -n "${SWIFTTUI_SWIFT_SDKS_PATH:-}" ]; then
    build_command+=(--swift-sdks-path "$SWIFTTUI_SWIFT_SDKS_PATH")
  fi

  printf '\n'
  android_note "step $step_number/${#steps[@]}: cross-compile $android_host_target for $triple ($step_engine build engine)"
  evidence "command[$label]: swiftly run swift ${build_command[*]}"
  started=$(date +%s)
  result=success
  detail=""
  rm -f "$raw_log" "$status_file" "$timeout_file"
  if [ "$step_engine" = "default" ] && detail="$(ndk_linker_problem)" && [ -n "$detail" ]; then
    result=failure
    printf '%s\n' "$detail" >"$raw_log"
  else
    status=0
    run_logged_command "$raw_log" "$status_file" "$timeout_file" \
      swiftly run swift "${build_command[@]}" || status="$(read_step_exit_code "$status_file")"
    if [ -f "$timeout_file" ]; then
      result=failure
      detail="swift build was killed by the step watchdog: it $(cat "$timeout_file")"
    elif [ "$status" -ne 0 ]; then
      result=failure
      detail="swift build exited $status"
    elif ! detail="$(verify_objects "$triple" "$raw_log")"; then
      result=failure
    fi
  fi
  duration=$(($(date +%s) - started))

  # Each build log opens with the environment it ran in and closes with its
  # verdict, so one file is the whole record for its step.
  {
    cat "$environment_file"
    printf '\n$ swiftly run swift %s\n' "${build_command[*]}"
    cat "$raw_log"
    printf '\nverdict[%s]: %s in %ss — %s\n' "$label" "$result" "$duration" "$detail"
  } >"$build_log"
  rm -f "$raw_log" "$status_file"
  evidence "verdict[$label]: $result in ${duration}s — $detail"
  printf '%s|%s|%s|%s|%s\n' "$triple" "$step_engine" "$result" "$duration" "$detail" >"$verdict_file"

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      printf '### Android cross-compile: `%s` (%s build engine)\n\n' "$triple" "$step_engine"
      printf '| Result | Duration | Toolchain | Swift SDK | NDK |\n| --- | --- | --- | --- | --- |\n'
      printf '| %s | %ss | %s | `%s` | `%s` |\n\n' \
        "$result" "$duration" "$android_toolchain_description" "$android_swift_sdk_id" "$ndk_revision"
    } >>"$GITHUB_STEP_SUMMARY"
  fi
  if [ "$result" != "success" ]; then
    failed_steps+=("$step")
    android_note "FAILED: $step — $detail (log: $build_log)"
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      printf '::error::%s does not cross-compile for %s (%s build engine): %s\n' \
        "$android_host_target" "$triple" "$step_engine" "$detail"
    fi
  fi
done

printf '\n'
if [ "${#failed_steps[@]}" -ne 0 ]; then
  android_note "FAILED: $android_host_target does not cross-compile for: ${failed_steps[*]}"
  android_note "evidence: $log_dir"
  exit 1
fi
android_note "OK: $android_host_target cross-compiles for: ${steps[*]}"
android_note "evidence: $log_dir"
