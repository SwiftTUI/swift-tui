#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp_root=${TMPDIR:-/tmp}
tmp_dir=$(mktemp -d "$tmp_root/swift-tui-ci-summary.XXXXXX")

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT

expected_file=$tmp_dir/expected.txt
results_dir=$tmp_dir/results
summary_file=$tmp_dir/summary.md
golden_file=$tmp_dir/golden.md

mkdir -p "$results_dir"

cat >"$expected_file" <<'EOF'
policy|Policy lane|Linux|amd64|ubuntu-24.04|SWIFTTUI_SKIP_PUBLIC_API_BASELINE=1 sh ./Scripts/test_gate.sh --lane policy --skip-bun-install
core|Core lane|Linux|amd64|ubuntu-24.04 (swift-tui-linux image)|SWIFTTUI_SKIP_PUBLIC_API_BASELINE=1 SWIFTTUI_SKIP_TERMUIPERF=1 sh ./Scripts/test_gate.sh --lane core
runtime-A|Runtime shard A|Linux|amd64|ubuntu-24.04 (swift-tui-linux image)|sh ./Scripts/test_gate.sh --lane runtime:A
runtime-A-arm64|Runtime shard A|Linux|arm64|ubuntu-24.04-arm (swift-tui-linux image)|sh ./Scripts/test_gate.sh --lane runtime:A
EOF

cat >"$results_dir/policy.result" <<'EOF'
policy|success|95
EOF

cat >"$results_dir/core.result" <<'EOF'
core|success|840
EOF

cat >"$results_dir/runtime-A.result" <<'EOF'
runtime-A|failure|65
EOF

cat >"$results_dir/runtime-A-arm64.result" <<'EOF'
runtime-A-arm64|success
EOF

cat >"$golden_file" <<'EOF'
## CI Test Matrix

| Lane | Platform | Arch | Runner | Result | Duration | Command |
| --- | --- | --- | --- | --- | --- | --- |
| Policy lane | Linux | amd64 | ubuntu-24.04 | success | 1m 35s | `SWIFTTUI_SKIP_PUBLIC_API_BASELINE=1 sh ./Scripts/test_gate.sh --lane policy --skip-bun-install` |
| Core lane | Linux | amd64 | ubuntu-24.04 (swift-tui-linux image) | success | 14m 0s | `SWIFTTUI_SKIP_PUBLIC_API_BASELINE=1 SWIFTTUI_SKIP_TERMUIPERF=1 sh ./Scripts/test_gate.sh --lane core` |
| Runtime shard A | Linux | amd64 | ubuntu-24.04 (swift-tui-linux image) | failure | 1m 5s | `sh ./Scripts/test_gate.sh --lane runtime:A` |
| Runtime shard A | Linux | arm64 | ubuntu-24.04-arm (swift-tui-linux image) | success | - | `sh ./Scripts/test_gate.sh --lane runtime:A` |

Overall result: failure (3 success, 1 failure)
EOF

"$repo_root/Scripts/render_ci_test_matrix_summary.sh" \
  "$expected_file" \
  "$results_dir" \
  "$summary_file"

diff -u "$golden_file" "$summary_file"
