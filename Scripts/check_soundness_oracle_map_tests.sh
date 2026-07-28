#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
checker="$repo_root/Scripts/check_soundness_oracle_map.sh"
canonical_map="$repo_root/docs/SOUNDNESS-ORACLES.md"
configuration="$repo_root/Sources/SwiftTUIGraph/Resolve/SoundnessProbeConfiguration.swift"
handler_oracle="$repo_root/Sources/SwiftTUIGraph/Resolve/CommittedHandlerResolutionOracle.swift"

scratch_root=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-oracle-map-tests.XXXXXX")
trap 'rm -rf "$scratch_root"' EXIT HUP INT TERM

run_expect_success() {
  title=$1
  map_path=$2

  if ! "$checker" "$map_path" "$configuration" "$handler_oracle" \
    >"$scratch_root/stdout" 2>"$scratch_root/stderr"
  then
    >&2 echo "FAIL: $title unexpectedly failed"
    >&2 cat "$scratch_root/stdout"
    >&2 cat "$scratch_root/stderr"
    exit 1
  fi
  echo "PASS: $title"
}

run_expect_failure() {
  title=$1
  map_path=$2
  expected_fragment=$3

  if "$checker" "$map_path" "$configuration" "$handler_oracle" \
    >"$scratch_root/stdout" 2>"$scratch_root/stderr"
  then
    >&2 echo "FAIL: $title unexpectedly passed"
    exit 1
  fi
  if ! grep -F "$expected_fragment" "$scratch_root/stderr" >/dev/null; then
    >&2 echo "FAIL: $title did not report '$expected_fragment'"
    >&2 cat "$scratch_root/stdout"
    >&2 cat "$scratch_root/stderr"
    exit 1
  fi
  echo "PASS: $title"
}

run_expect_success "canonical map" "$canonical_map"

deleted_map="$scratch_root/deleted.md"
awk '
  /oracle-map: stamp-coherence[[:space:]]*;/ { next }
  { print }
' "$canonical_map" >"$deleted_map"
run_expect_failure "deleted row" "$deleted_map" "missing map kind: stamp-coherence"

missing_recorder_map="$scratch_root/missing-recorder.md"
sed \
  's/oracle-map: stamp-coherence ; recordStampCoherenceViolation/oracle-map: stamp-coherence ; recordMissingStampRecorder/' \
  "$canonical_map" >"$missing_recorder_map"
run_expect_failure \
  "missing recorder" \
  "$missing_recorder_map" \
  "missing recorder: recordStampCoherenceViolation"

duplicate_map="$scratch_root/duplicate.md"
cp "$canonical_map" "$duplicate_map"
printf '%s\n' \
  '<!-- oracle-map: stamp-coherence ; recordStampCoherenceViolation ; stampCoherenceViolationCount -->' \
  >>"$duplicate_map"
run_expect_failure "duplicate row" "$duplicate_map" "duplicate map kind: stamp-coherence"

unknown_map="$scratch_root/unknown.md"
cp "$canonical_map" "$unknown_map"
printf '%s\n' \
  '<!-- oracle-map: invented-oracle ; recordInventedViolation ; inventedViolationCount -->' \
  >>"$unknown_map"
run_expect_failure "unknown row" "$unknown_map" "unknown map kind: invented-oracle"

echo "Soundness oracle map fixture tests passed."
