#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
map_path=${1:-"$repo_root/docs/SOUNDNESS-ORACLES.md"}
configuration=${2:-"$repo_root/Sources/SwiftTUIGraph/Resolve/SoundnessProbeConfiguration.swift"}
handler_oracle=${3:-"$repo_root/Sources/SwiftTUIGraph/Resolve/CommittedHandlerResolutionOracle.swift"}

scratch_root=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-oracle-map.XXXXXX")
trap 'rm -rf "$scratch_root"' EXIT HUP INT TERM

for required_path in "$map_path" "$configuration" "$handler_oracle"; do
  if [ ! -f "$required_path" ]; then
    >&2 echo "soundness oracle map check: missing input: $required_path"
    exit 1
  fi
done

expected_kinds="$scratch_root/expected-kinds"
expected_recorders="$scratch_root/expected-recorders"
expected_counters="$scratch_root/expected-counters"
map_rows="$scratch_root/map-rows"
map_kinds="$scratch_root/map-kinds"
map_recorders="$scratch_root/map-recorders"
map_counters="$scratch_root/map-counters"

sed -n 's/.*emitTrace("\([^"]*\)").*/\1/p' "$configuration" >"$expected_kinds"
sed -n \
  '/package enum InteractiveHandlerResolutionFamily/,/^}/s/^[[:space:]]*case \([a-z][a-z]*\)$/handler-resolution-\1/p' \
  "$handler_oracle" >>"$expected_kinds"
if grep -F "func recordAutomaticLifetimeAnchor" "$configuration" >/dev/null; then
  echo "automatic-lifetime-anchor" >>"$expected_kinds"
fi
LC_ALL=C sort -u -o "$expected_kinds" "$expected_kinds"

sed -n \
  's/^[[:space:]]*package static func \(record[A-Za-z0-9_]*\).*/\1/p' \
  "$configuration" |
  LC_ALL=C sort -u >"$expected_recorders"

sed -n \
  's/^[[:space:]]*package static var \([A-Za-z0-9_]*Count\) = 0$/\1/p' \
  "$configuration" |
  LC_ALL=C sort -u >"$expected_counters"

awk '
  /<!--[[:space:]]*oracle-map:/ {
    row = $0
    sub(/^.*<!--[[:space:]]*oracle-map:[[:space:]]*/, "", row)
    sub(/[[:space:]]*-->.*$/, "", row)
    count = split(row, fields, /;/)
    if (count != 3) {
      printf "malformed oracle-map metadata: %s\n", $0 > "/dev/stderr"
      malformed = 1
      next
    }
    for (field_index = 1; field_index <= 3; field_index += 1) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", fields[field_index])
    }
    print fields[1] "|" fields[2] "|" fields[3]
  }
  END {
    if (malformed) {
      exit 1
    }
  }
' "$map_path" >"$map_rows"

if [ ! -s "$map_rows" ]; then
  >&2 echo "soundness oracle map check: no oracle-map metadata rows found"
  exit 1
fi

awk -F '|' '{ print $1 }' "$map_rows" | LC_ALL=C sort >"$map_kinds"
awk -F '|' '{ print $2 }' "$map_rows" |
  awk '{ count = split($0, values, /,/); for (item_index = 1; item_index <= count; item_index += 1) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", values[item_index]); if (values[item_index] != "") print values[item_index] } }' |
  LC_ALL=C sort -u >"$map_recorders"
awk -F '|' '{ print $3 }' "$map_rows" |
  awk '{ count = split($0, values, /,/); for (item_index = 1; item_index <= count; item_index += 1) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", values[item_index]); if (values[item_index] != "") print values[item_index] } }' |
  LC_ALL=C sort -u >"$map_counters"

failed=0

while IFS= read -r duplicate_kind; do
  [ -n "$duplicate_kind" ] || continue
  >&2 echo "duplicate map kind: $duplicate_kind"
  failed=1
done <<EOF
$(uniq -d "$map_kinds")
EOF

while IFS= read -r missing_kind; do
  [ -n "$missing_kind" ] || continue
  >&2 echo "missing map kind: $missing_kind"
  failed=1
done <<EOF
$(comm -23 "$expected_kinds" "$map_kinds")
EOF

while IFS= read -r unknown_kind; do
  [ -n "$unknown_kind" ] || continue
  >&2 echo "unknown map kind: $unknown_kind"
  failed=1
done <<EOF
$(comm -13 "$expected_kinds" "$map_kinds")
EOF

while IFS= read -r missing_recorder; do
  [ -n "$missing_recorder" ] || continue
  >&2 echo "missing recorder: $missing_recorder"
  failed=1
done <<EOF
$(comm -23 "$expected_recorders" "$map_recorders")
EOF

while IFS= read -r unknown_recorder; do
  [ -n "$unknown_recorder" ] || continue
  >&2 echo "unknown recorder: $unknown_recorder"
  failed=1
done <<EOF
$(comm -13 "$expected_recorders" "$map_recorders")
EOF

while IFS= read -r missing_counter; do
  [ -n "$missing_counter" ] || continue
  >&2 echo "missing counter: $missing_counter"
  failed=1
done <<EOF
$(comm -23 "$expected_counters" "$map_counters")
EOF

while IFS= read -r unknown_counter; do
  [ -n "$unknown_counter" ] || continue
  >&2 echo "unknown counter: $unknown_counter"
  failed=1
done <<EOF
$(comm -13 "$expected_counters" "$map_counters")
EOF

if [ "$failed" -ne 0 ]; then
  exit 1
fi

row_count=$(wc -l <"$map_kinds" | tr -d ' ')
trace_count=$((row_count - 1))
counter_count=$(wc -l <"$expected_counters" | tr -d ' ')
echo "Soundness oracle map covers $trace_count trace kinds, 1 informational kind, and $counter_count counters."
