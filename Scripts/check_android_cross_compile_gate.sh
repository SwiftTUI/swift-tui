#!/usr/bin/env sh

set -eu

# Self-test for Scripts/check_android_cross_compile.sh.
#
# The Android gate exists so an Android-only break cannot ship behind green
# desktop checks, and it is only worth that if it cannot pass vacuously. Each
# case below takes one thing away — the toolchain, the Swift SDK, the NDK, the
# sysroot link, the compile, the objects — and requires a red verdict with the
# reason in it. A gate edited to skip, warn or pass in any of those states
# fails here, in the policy lane, without a Swift toolchain or an NDK.
#
# Everything runs against a fake swiftly, a fake Swift SDK bundle and fake
# NDKs under a temporary directory, with PATH reduced to the fakes and the
# system tools. The real toolchain and SDKs are never touched.

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
gate="$repo_root/Scripts/check_android_cross_compile.sh"

# shellcheck source=Scripts/lib/android_cross_compile_pins.sh
. "$repo_root/Scripts/lib/android_cross_compile_pins.sh"
arm64=aarch64-unknown-linux-android28
other_ndk_version=27.3.13750724

work=$(mktemp -d "${TMPDIR:-/tmp}/swifttui-android-gate-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
fake="$work/fake"
bundle="$fake/bundle/swift-android"
mkdir -p "$work/bin" "$work/home" "$work/empty-android-sdk"

# The fake reads its behaviour from files under $FAKE_ROOT, so a case is a few
# file writes. `build` records what it was asked and with which NDK, then
# emits objects for the requested triple unless the case says otherwise.
cat >"$work/bin/swiftly" <<'STUB'
#!/bin/sh
set -eu
root=$FAKE_ROOT
if [ "$1" = "--version" ]; then
  echo "1.1.4"
  exit 0
fi
if [ "$1" != "run" ] || [ "$2" != "swift" ]; then
  echo "fake swiftly: unexpected arguments: $*" >&2
  exit 64
fi
shift 2
elf_object() {
  printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\001\000' >"$2"
  printf "$1" >>"$2"
}
case "$1" in
--version)
  printf 'Swift version %s (swift-RELEASE)\nTarget: x86_64-unknown-linux-gnu\n' "$(cat "$root/swift-version")"
  ;;
sdk)
  case "$2" in
  list) cat "$root/sdk-list" ;;
  configure) printf 'sdkRootPath: %s\n' "$root/bundle/swift-android/ndk-sysroot" ;;
  *) exit 64 ;;
  esac
  ;;
build)
  case " $* " in
  *" --show-bin-path "*)
    printf '%s\n' "$root/products"
    exit 0
    ;;
  esac
  printf '%s\n' "$*" >>"$root/build-invocations"
  printf '%s\n' "${ANDROID_NDK_HOME-<unset>}" >"$root/build-ndk-home"
  echo "Building for debugging..."
  status=$(cat "$root/build-exit")
  if [ "$status" -ne 0 ]; then
    echo "error: fake compile failure"
    exit "$status"
  fi
  rm -rf "$root/products"
  mkdir -p "$root/products"
  emits=$(cat "$root/build-emits")
  if [ "$emits" = "requested" ]; then
    case " $* " in
    *" --triple aarch64-"*) emits=aarch64 ;;
    *" --triple x86_64-"*) emits=x86_64 ;;
    esac
  fi
  case "$emits" in
  aarch64) elf_object '\267\000' "$root/products/SwiftTUIAndroidHost.o" ;;
  x86_64) elf_object '\076\000' "$root/products/SwiftTUIAndroidHost.o" ;;
  mach-o) printf '\317\372\355\376\014\000\000\001\000\000\000\000\001\000\000\000\000\000\000\000' >"$root/products/SwiftTUIAndroidHost.o" ;;
  nothing) ;;
  esac
  echo "Build complete!"
  ;;
*)
  echo "fake swiftly: unexpected swift subcommand: $*" >&2
  exit 64
  ;;
esac
STUB
chmod +x "$work/bin/swiftly"

# make_ndk <directory> <major> <minor> <build>
make_ndk() {
  mn_prebuilt="$1/toolchains/llvm/prebuilt/fake-host"
  mkdir -p "$mn_prebuilt/sysroot/usr/include/android" "$mn_prebuilt/lib/clang/21/include" "$mn_prebuilt/bin"
  printf 'Pkg.Desc = Android NDK\nPkg.Revision = %s.%s.%s\n' "$2" "$3" "$4" >"$1/source.properties"
  printf '#define __NDK_MAJOR__ %s\n#define __NDK_MINOR__ %s\n#define __NDK_BUILD__ %s\n' "$2" "$3" "$4" \
    >"$mn_prebuilt/sysroot/usr/include/android/ndk-version.h"
  : >"$mn_prebuilt/sysroot/usr/include/semaphore.h"
  : >"$mn_prebuilt/lib/clang/21/include/stddef.h"
  printf '#!/bin/sh\nexit 0\n' >"$mn_prebuilt/bin/ld.lld"
  chmod +x "$mn_prebuilt/bin/ld.lld"
}

# make_versioned_ndk <directory> <major.minor.build>
make_versioned_ndk() {
  mvn_rest=$2
  mvn_major=${mvn_rest%%.*}
  mvn_rest=${mvn_rest#*.}
  make_ndk "$1" "$mvn_major" "${mvn_rest%%.*}" "${mvn_rest#*.}"
}

pinned_ndk="$work/android-sdk/ndk/$android_ndk_pinned_version"
other_ndk="$work/android-sdk/ndk/$other_ndk_version"

# Restores the healthy state: pinned toolchain, SDK listed and freshly
# installed (no ndk-sysroot), pinned NDK present, compile succeeds.
reset_fakes() {
  rm -rf "$fake" "$work/android-sdk"
  mkdir -p "$bundle/scripts" "$bundle/swift-resources/usr/lib/swift"
  tr -d '[:space:]' <"$repo_root/.swift-version" >"$fake/swift-version"
  printf '%s\nswift-0.0.0-RELEASE_wasm\n' "$android_swift_sdk_id" >"$fake/sdk-list"
  printf '0\n' >"$fake/build-exit"
  printf 'requested\n' >"$fake/build-emits"
  # Links the sysroot the way the real setup-android-sdk.sh does, `ln -sf`
  # onto the clang resource link included.
  cat >"$bundle/scripts/setup-android-sdk.sh" <<'SETUP'
#!/usr/bin/env bash
set -e
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  echo "setup-android-sdk.sh: error: missing environment variable ANDROID_NDK_HOME"
  exit 1
fi
if [ -f "$FAKE_ROOT/setup-exit" ]; then
  echo "setup-android-sdk.sh: error: fake setup failure"
  exit "$(cat "$FAKE_ROOT/setup-exit")"
fi
cd "$(dirname "$(dirname "$0")")"
rm -rf ndk-sysroot
mkdir -p ndk-sysroot/usr
ln -s "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/sysroot/usr/include ndk-sysroot/usr/include
ln -sf "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/lib/clang/* swift-resources/usr/lib/swift/clang
echo ran >>"$FAKE_ROOT/setup-runs"
echo "setup-android-sdk.sh: success"
SETUP
  make_versioned_ndk "$pinned_ndk" "$android_ndk_pinned_version"
  make_versioned_ndk "$other_ndk" "$other_ndk_version"
}

failures=0
cases=0

fail() {
  echo >&2 "FAIL: $case_name: $*"
  failures=$((failures + 1))
}

# run_gate <case name> [VAR=value...] -- [gate arguments...]
# Runs the gate against the fakes and records its exit status and output.
run_gate() {
  case_name=$1
  shift
  cases=$((cases + 1))
  gate_path="$work/bin:/usr/bin:/bin"
  gate_environment=""
  while [ "$1" != "--" ]; do
    case "$1" in
    PATH=*) gate_path=${1#PATH=} ;;
    *) gate_environment="$gate_environment $1" ;;
    esac
    shift
  done
  shift
  log="$work/$case_name.log"
  evidence="$work/evidence/$case_name"
  status=0
  # shellcheck disable=SC2086
  env -i PATH="$gate_path" HOME="$work/home" TMPDIR="${TMPDIR:-/tmp}" FAKE_ROOT="$fake" \
    ANDROID_HOME="$work/android-sdk" SWIFTTUI_ANDROID_LOG_DIR="$evidence" \
    SWIFTTUI_ANDROID_SCRATCH_PATH="$work/scratch" SWIFTTUI_ANDROID_STEP_TIMEOUT_SECONDS=0 \
    $gate_environment "$gate" "$@" >"$log" 2>&1 || status=$?
}

expect_status() {
  if [ "$status" -ne "$1" ]; then
    sed 's/^/    /' "$log" >&2
    fail "exited $status, expected $1"
  fi
}

expect_output() {
  grep -qF -- "$1" "$log" || fail "output does not say '$1'"
}

expect_no_build() {
  [ ! -e "$fake/build-invocations" ] || fail "ran swift build although the tooling check failed"
}

expect_verdict() {
  grep -q "|$3|" "$evidence/verdict-$1-$2.txt" 2>/dev/null ||
    fail "verdict-$1-$2.txt does not record '$3'"
}

setup_runs() {
  if [ -f "$fake/setup-runs" ]; then
    wc -l <"$fake/setup-runs" | tr -d ' '
  else
    echo 0
  fi
}

# --- the healthy path, so every red case below is red for its own reason -----
reset_fakes
run_gate fresh-sdk-passes SWIFTTUI_ANDROID_STEP_TIMEOUT_SECONDS=300 -- --triple "$arm64"
expect_status 0
expect_verdict "$arm64" default success
[ "$(setup_runs)" = "1" ] || fail "a fresh SDK's sysroot was not materialized through the bundle's setup script"
grep -qF -- "--triple $arm64 --target $android_host_target" "$fake/build-invocations" ||
  fail "did not build --target $android_host_target for $arm64"
grep -qF -- "--product" "$fake/build-invocations" && fail "built a product instead of the target"
[ "$(cat "$fake/build-ndk-home")" = "$pinned_ndk" ] ||
  fail "did not export the pinned NDK to the build (ANDROID_NDK_HOME=$(cat "$fake/build-ndk-home"))"
grep -qF "sysroot_ndk_version: $android_ndk_pinned_version" "$evidence/build-$arm64-default.log" ||
  fail "the build log does not open with the environment it ran in"

run_gate materialized-sysroot-is-left-alone -- --triple "$arm64" --build-system native
expect_status 0
expect_verdict "$arm64" native success
[ "$(setup_runs)" = "1" ] || fail "re-ran the setup script on a sysroot that already matched the pinned NDK"
grep -qF -- "--build-system native" "$fake/build-invocations" || fail "did not select the native build engine"

reset_fakes
run_gate default-plan-runs-every-step --
expect_status 0
for step in $android_default_steps; do
  expect_verdict "${step%%:*}" "${step##*:}" success
done

# --- missing tooling fails, and stops before any compile ---------------------
reset_fakes
run_gate swiftly-missing PATH=/usr/bin:/bin -- --triple "$arm64"
expect_status 1
expect_output "swiftly is not on PATH"
expect_no_build

reset_fakes
printf '0.0.1\n' >"$fake/swift-version"
run_gate toolchain-drift -- --triple "$arm64"
expect_status 1
expect_output "toolchain drift"
expect_no_build

reset_fakes
printf 'swift-0.0.0-RELEASE_wasm\n' >"$fake/sdk-list"
run_gate swift-sdk-missing -- --triple "$arm64"
expect_status 1
expect_output "'$android_swift_sdk_id' is not installed"
expect_output "swift sdk install $android_swift_sdk_url --checksum $android_swift_sdk_sha256"
expect_no_build

reset_fakes
printf '%s-other\n' "$android_swift_sdk_id" >"$fake/sdk-list"
run_gate swift-sdk-id-must-match-exactly -- --triple "$arm64"
expect_status 1
expect_no_build

reset_fakes
run_gate ndk-missing ANDROID_HOME="$work/empty-android-sdk" -- --triple "$arm64"
expect_status 1
expect_output "Android NDK $android_ndk_pinned_version not found"
expect_no_build

reset_fakes
run_gate ndk-other-version ANDROID_NDK_HOME="$other_ndk" -- --triple "$arm64"
expect_status 1
expect_output "is $other_ndk_version, but the gate requires $android_ndk_pinned_version"
expect_no_build

# --- a sysroot linked to another NDK fails, and is relinked only on request --
reset_fakes
(cd "$bundle" && FAKE_ROOT="$fake" ANDROID_NDK_HOME="$other_ndk" bash scripts/setup-android-sdk.sh >/dev/null)
run_gate sysroot-linked-to-other-ndk -- --triple "$arm64"
expect_status 1
expect_output "its headers are NDK $other_ndk_version, not $android_ndk_pinned_version"
expect_no_build
[ "$(setup_runs)" = "1" ] || fail "relinked the sysroot without SWIFTTUI_ANDROID_RELINK_SYSROOT=1"

run_gate sysroot-relinked-on-request SWIFTTUI_ANDROID_RELINK_SYSROOT=1 -- --triple "$arm64" --build-system native
expect_status 0
[ "$(setup_runs)" = "2" ] || fail "SWIFTTUI_ANDROID_RELINK_SYSROOT=1 did not re-run the setup script"
case "$(cd -P "$bundle/swift-resources/usr/lib/swift/clang" && pwd -P)" in
"$(cd -P "$pinned_ndk" && pwd -P)"/*) ;;
*) fail "the relink left the clang resource directory on the other NDK" ;;
esac
[ ! -e "$other_ndk/toolchains/llvm/prebuilt/fake-host/lib/clang/21/21" ] ||
  fail "the relink wrote a link into the other NDK"

reset_fakes
printf '3\n' >"$fake/setup-exit"
run_gate sysroot-setup-fails -- --triple "$arm64"
expect_status 1
expect_output "setup-android-sdk.sh exited 3"
expect_no_build

# --- a failed, empty or host-targeted compile fails --------------------------
reset_fakes
printf '1\n' >"$fake/build-exit"
run_gate compile-fails -- --triple "$arm64"
expect_status 1
expect_output "swift build exited 1"
expect_verdict "$arm64" default failure
grep -qF "error: fake compile failure" "$evidence/build-$arm64-default.log" ||
  fail "the retained build log does not hold the compiler's error"

reset_fakes
printf 'nothing\n' >"$fake/build-emits"
run_gate compile-produces-nothing -- --triple "$arm64"
expect_status 1
expect_output "left no $android_host_target object"
expect_verdict "$arm64" default failure

reset_fakes
printf 'x86_64\n' >"$fake/build-emits"
run_gate compile-for-another-architecture -- --triple "$arm64"
expect_status 1
expect_output "is not an ELF object for $arm64"

reset_fakes
printf 'mach-o\n' >"$fake/build-emits"
run_gate compile-for-the-host -- --triple "$arm64" --build-system native
expect_status 1
expect_output "is not an ELF object for $arm64"
expect_verdict "$arm64" native failure

# --- the default engine needs the NDK's own linker to run on this host -------
reset_fakes
printf '#!/bin/sh\nexit 126\n' >"$pinned_ndk/toolchains/llvm/prebuilt/fake-host/bin/ld.lld"
run_gate ndk-linker-cannot-run -- --triple "$arm64"
expect_status 1
expect_output "cannot run on this"
expect_no_build
run_gate native-engine-needs-no-ndk-linker -- --triple "$arm64" --build-system native
expect_status 0

# --- misuse is rejected rather than run as something else --------------------
reset_fakes
run_gate build-system-without-triple -- --build-system native
expect_status 2
run_gate unknown-triple -- --triple wasm32-unknown-wasi
expect_status 2
run_gate unknown-build-system -- --triple "$arm64" --build-system xcode
expect_status 2
run_gate unknown-argument -- --skip
expect_status 2
expect_no_build

if [ "$failures" -ne 0 ]; then
  echo >&2 "check_android_cross_compile_gate: $failures assertion(s) failed in $cases cases"
  exit 1
fi

echo "check_android_cross_compile_gate: OK ($cases cases)"
