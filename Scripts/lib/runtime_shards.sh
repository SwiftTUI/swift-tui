#!/usr/bin/env sh

# Readers for the runtime-lane shard manifest (Scripts/data/runtime-shards.txt).
#
# Sourced by Scripts/test_all.sh (the repo gate's `runtime:<shard>` lanes and
# the isolated-suite skip list of its `all` lane) and by
# Scripts/release_soundness_lane.sh (the release lane's serialized shards). One
# reader for one manifest, so the two lanes cannot partition the SwiftTUITests
# surface differently. Scripts/check_root_test_target_coverage.sh parses the
# same file independently and fails the policy lane when a suite is claimed by
# no shard or a shard claims nothing.
#
# Rows are `<shard-id>|<regex>` (ordered, first match wins) or
# `isolated|<SuiteType>`. Regexes may contain `|`, so split on the FIRST bar
# only. Comments and blank lines are ignored.
#
# Callers set `runtime_shard_manifest` (an absolute path) before sourcing.

if [ -z "${runtime_shard_manifest:-}" ]; then
  >&2 echo "Scripts/lib/runtime_shards.sh: set runtime_shard_manifest before sourcing."
  exit 1
fi

manifest_rows() {
  if [ ! -f "$runtime_shard_manifest" ]; then
    >&2 echo "Missing runtime shard manifest: $runtime_shard_manifest"
    exit 1
  fi
  grep -v '^[[:space:]]*#' "$runtime_shard_manifest" | grep -v '^[[:space:]]*$'
}

manifest_shard_ids() {
  manifest_rows | awk '{ id = $0; sub(/\|.*/, "", id); if (id != "isolated") print id }'
}

manifest_shard_regex() {
  manifest_rows | awk -v id="$1" '
    { row_id = $0; sub(/\|.*/, "", row_id) }
    row_id == id { print substr($0, length(row_id) + 2); exit }
  '
}

manifest_isolated_suites() {
  manifest_rows | awk '{ id = $0; sub(/\|.*/, "", id); if (id == "isolated") print substr($0, length(id) + 2) }'
}

# Prints, one per line, the `swift test` selection arguments for one shard:
# `--filter <its regex>`, `--skip <regex>` for every shard listed above it in
# the manifest (first match wins, so an earlier shard's suites are never
# re-run here), and `--skip <suite>` for every isolated suite.
runtime_shard_test_args() {
  shard=$1
  printf '%s\n' --filter "$(manifest_shard_regex "$shard")"
  for earlier_shard in $(manifest_shard_ids); do
    if [ "$earlier_shard" = "$shard" ]; then
      break
    fi
    printf '%s\n' --skip "$(manifest_shard_regex "$earlier_shard")"
  done
  for isolated_suite in $(manifest_isolated_suites); do
    printf '%s\n' --skip "$isolated_suite"
  done
}
