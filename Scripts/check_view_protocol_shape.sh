#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

swiftly run swift build --target SwiftTUI >/dev/null
BIN_PATH="$(swiftly run swift build --show-bin-path)"
MODULE_PATH="${BIN_PATH}/Modules"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macosx15.0"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/swifttui-view-shape.XXXXXX")"
cleanup() {
  rm -rf "${WORKDIR}"
}
trap cleanup EXIT

run_probe() {
  local name="$1"
  local expected="$2"
  local source="$3"
  local file="${WORKDIR}/${name}.swift"
  local log="${WORKDIR}/${name}.log"

  printf "%s\n" "${source}" >"${file}"

  set +e
  swiftly run swiftc \
    -typecheck \
    -swift-version 6 \
    -I "${MODULE_PATH}" \
    -I "${BIN_PATH}" \
    -L "${BIN_PATH}" \
    -target "${TARGET}" \
    -sdk "${SDK_PATH}" \
    "${file}" >"${log}" 2>&1
  local status=$?
  set -e

  case "${expected}:${status}" in
    pass:0)
      printf "[view-protocol-shape] PASS expected compile success: %s\n" "${name}"
      ;;
    fail:0)
      printf "[view-protocol-shape] FAIL expected compile failure: %s\n" "${name}" >&2
      cat "${log}" >&2
      exit 1
      ;;
    fail:*)
      printf "[view-protocol-shape] PASS expected compile failure: %s\n" "${name}"
      ;;
    pass:*)
      printf "[view-protocol-shape] FAIL expected compile success: %s\n" "${name}" >&2
      cat "${log}" >&2
      exit 1
      ;;
  esac
}

run_probe "empty-view-fails" "fail" 'import SwiftTUI
struct EmptyUserView: View {}
'

run_probe "explicit-never-view-fails" "fail" 'import SwiftTUI
struct ExplicitNeverUserView: View {
  typealias Body = Never
}
'

run_probe "body-view-passes" "pass" 'import SwiftTUI
struct BodyUserView: View {
  var body: some View {
    Text("ok")
  }
}
'

run_probe "primitive-builtins-pass" "pass" 'import SwiftTUI
func accept<V: View>(_ view: V) {}
accept(Text("ok"))
accept(EmptyView())
accept(Group { Text("ok") })
accept(Rectangle())
'

run_probe "empty-modifier-fails" "fail" 'import SwiftTUI
struct EmptyUserModifier: ViewModifier {}
'

run_probe "explicit-never-modifier-passes" "pass" 'import SwiftTUI
struct ExplicitPrimitiveModifier: ViewModifier {
  typealias Body = Never
}
'
