#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

declared_targets=$(mktemp "/tmp/swift-tui-declared-test-targets.XXXXXX")
covered_targets=$(mktemp "/tmp/swift-tui-covered-test-targets.XXXXXX")
missing_targets=$(mktemp "/tmp/swift-tui-missing-test-targets.XXXXXX")
extra_targets=$(mktemp "/tmp/swift-tui-extra-test-targets.XXXXXX")

cleanup() {
  rm -f "$declared_targets" "$covered_targets" "$missing_targets" "$extra_targets"
}

trap cleanup EXIT

awk '
  /\.testTarget\(/ {
    in_test_target = 1
  }

  in_test_target && /name:[[:space:]]*"[^"]+"/ {
    line = $0
    sub(/^.*name:[[:space:]]*"/, "", line)
    sub(/".*$/, "", line)
    print line
    in_test_target = 0
  }
' Package.swift | LC_ALL=C sort -u >"$declared_targets"

awk '
  {
    for (field_index = 1; field_index <= NF; field_index += 1) {
      if ($field_index == "--filter" && (field_index + 1) <= NF) {
        target = $(field_index + 1)
        gsub(/["\\]/, "", target)
        if (target ~ /^[A-Za-z0-9_]+Tests$/) {
          print target
        }
      }
    }
  }
' Scripts/test_all.sh | LC_ALL=C sort -u >"$covered_targets"

comm -23 "$declared_targets" "$covered_targets" >"$missing_targets"
comm -13 "$declared_targets" "$covered_targets" >"$extra_targets"

if [ -s "$missing_targets" ] || [ -s "$extra_targets" ]; then
  if [ -s "$missing_targets" ]; then
    >&2 echo "Root test targets declared in Package.swift but not covered by Scripts/test_all.sh:"
    >&2 sed 's/^/  - /' "$missing_targets"
  fi

  if [ -s "$extra_targets" ]; then
    >&2 echo "Scripts/test_all.sh filters test targets not declared in Package.swift:"
    >&2 sed 's/^/  - /' "$extra_targets"
  fi

  exit 1
fi

echo "All root Package.swift test targets are covered by Scripts/test_all.sh."

# --- Runtime shard census (plan 2026-08-25-001 Stage 1a) --------------------
# The serialized SwiftTUITests lane runs as shards in CI, selected by the
# regexes in Scripts/data/runtime-shards.txt (first match wins). A suite that
# matches no shard would silently fall out of CI, and a shard whose regex
# matches nothing would pass silently (`swift test --filter` with no match
# exits 0), so this census requires:
#   1. every SwiftTUITests suite type is claimed by some shard, and
#   2. every shard claims at least one non-isolated suite, and
#   3. every `isolated|` row names an existing suite type, and
#   4. every regex is valid ERE with no whitespace (it is re-split into
#      `swift test` arguments by test_all.sh).
# Suite types are the column-0 `struct`/`class`/`final class`/`enum`/`actor`
# declarations in Tests/SwiftTUITests files that contain `@Test` — the same
# `SwiftTUITests.<Type>` prefix swift-testing puts on the fully qualified test
# name (`SwiftTUITests.<Type>/<test>()`), which is what the regexes match.
manifest=Scripts/data/runtime-shards.txt
suite_names=$(mktemp "/tmp/swift-tui-runtime-suites.XXXXXX")
manifest_rows=$(mktemp "/tmp/swift-tui-runtime-shards.XXXXXX")
claims=$(mktemp "/tmp/swift-tui-runtime-claims.XXXXXX")
trap 'cleanup; rm -f "$suite_names" "$manifest_rows" "$claims"' EXIT

if [ ! -f "$manifest" ]; then
  >&2 echo "Missing runtime shard manifest: $manifest"
  exit 1
fi

grep -v '^[[:space:]]*#' "$manifest" | grep -v '^[[:space:]]*$' >"$manifest_rows"

grep -l '@Test' $(find Tests/SwiftTUITests -type f -name '*.swift') |
  xargs grep -hoE '^(final class|struct|enum|actor|class) [A-Za-z_][A-Za-z0-9_]*' |
  awk '{ print $NF }' | LC_ALL=C sort -u >"$suite_names"

if [ ! -s "$suite_names" ]; then
  >&2 echo "No SwiftTUITests suite types found; the census grep drifted."
  exit 1
fi

census_failed=0
shard_ids=""
while IFS= read -r row; do
  kind=${row%%|*}
  value=${row#*|}
  case "$kind" in
  "" | *[!A-Za-z0-9_-]*)
    >&2 echo "Invalid shard id in $manifest: '$row'"
    census_failed=1
    continue
    ;;
  esac
  case "$value" in
  "" | *[[:space:]]*)
    >&2 echo "Shard manifest value must be non-empty and whitespace-free: '$row'"
    census_failed=1
    continue
    ;;
  esac
  if [ "$kind" = isolated ]; then
    if ! grep -qx "$value" "$suite_names"; then
      >&2 echo "Isolated suite '$value' in $manifest is not a SwiftTUITests suite type."
      census_failed=1
    fi
    continue
  fi
  if ! printf 'probe\n' | grep -Eq "$value" 2>/dev/null &&
    ! printf 'probe\n' | grep -Evq "$value" 2>/dev/null; then
    >&2 echo "Shard '$kind' regex is not a valid extended regular expression: $value"
    census_failed=1
    continue
  fi
  shard_ids="$shard_ids $kind"
done <"$manifest_rows"

if [ -z "$shard_ids" ]; then
  >&2 echo "No shards defined in $manifest."
  exit 1
fi

# Claim every suite for the first shard whose regex matches its qualified name.
: >"$claims"
while IFS= read -r suite; do
  qualified="SwiftTUITests.$suite"
  claimed=""
  while IFS= read -r row; do
    kind=${row%%|*}
    [ "$kind" != isolated ] || continue
    regex=${row#*|}
    if printf '%s\n' "$qualified" | grep -Eq "$regex"; then
      claimed=$kind
      break
    fi
  done <"$manifest_rows"
  if [ -z "$claimed" ]; then
    >&2 echo "Suite $qualified matches no shard regex in $manifest."
    census_failed=1
    continue
  fi
  if grep -qx "$suite" <<EOF
$(awk -F '|' '$1 == "isolated" { print $2 }' "$manifest_rows")
EOF
  then
    printf '%s\t%s\tisolated\n' "$claimed" "$suite" >>"$claims"
  else
    printf '%s\t%s\tshard\n' "$claimed" "$suite" >>"$claims"
  fi
done <"$suite_names"

for shard in $shard_ids; do
  claimed_count=$(awk -F '\t' -v shard="$shard" '$1 == shard && $3 == "shard" { count += 1 } END { print count + 0 }' "$claims")
  isolated_count=$(awk -F '\t' -v shard="$shard" '$1 == shard && $3 == "isolated" { count += 1 } END { print count + 0 }' "$claims")
  if [ "$claimed_count" -eq 0 ]; then
    >&2 echo "Runtime shard '$shard' claims no suite: its regex matches nothing, so its lane would pass vacuously."
    census_failed=1
  fi
  echo "Runtime shard $shard: $claimed_count suite(s) (+ $isolated_count isolated, run in the core lane)"
done

if [ "$census_failed" -ne 0 ]; then
  exit 1
fi

echo "All $(wc -l <"$suite_names" | tr -d ' ') SwiftTUITests suite types are claimed by exactly one runtime shard."
