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
linux-amd64|Linux repo gate|Linux|amd64|ubuntu-24.04|STUI_SKIP_PUBLIC_API_BASELINE=1 STUI_SKIP_TERMUIPERF=1 sh ./Scripts/test_gate.sh --skip-bun-install
linux-arm64|Linux repo gate|Linux|arm64|ubuntu-24.04-arm|STUI_SKIP_PUBLIC_API_BASELINE=1 STUI_SKIP_TERMUIPERF=1 sh ./Scripts/test_gate.sh --skip-bun-install
macos|macOS repo gate|macOS|-|macos-26|STUI_SKIP_PUBLIC_API_BASELINE=1 STUI_SKIP_TERMUIPERF=1 sh ./Scripts/test_gate.sh --skip-bun-install
EOF

cat >"$results_dir/linux-amd64.result" <<'EOF'
linux-amd64|success|840
EOF

cat >"$results_dir/linux-arm64.result" <<'EOF'
linux-arm64|failure|65
EOF

cat >"$results_dir/macos.result" <<'EOF'
macos|success
EOF

cat >"$golden_file" <<'EOF'
## CI Test Matrix

| Lane | Platform | Arch | Runner | Result | Duration | Command |
| --- | --- | --- | --- | --- | --- | --- |
| Linux repo gate | Linux | amd64 | ubuntu-24.04 | success | 14m 0s | `STUI_SKIP_PUBLIC_API_BASELINE=1 STUI_SKIP_TERMUIPERF=1 sh ./Scripts/test_gate.sh --skip-bun-install` |
| Linux repo gate | Linux | arm64 | ubuntu-24.04-arm | failure | 1m 5s | `STUI_SKIP_PUBLIC_API_BASELINE=1 STUI_SKIP_TERMUIPERF=1 sh ./Scripts/test_gate.sh --skip-bun-install` |
| macOS repo gate | macOS | - | macos-26 | success | - | `STUI_SKIP_PUBLIC_API_BASELINE=1 STUI_SKIP_TERMUIPERF=1 sh ./Scripts/test_gate.sh --skip-bun-install` |

Overall result: failure (2 success, 1 failure)
EOF

"$repo_root/Scripts/render_ci_test_matrix_summary.sh" \
  "$expected_file" \
  "$results_dir" \
  "$summary_file"

diff -u "$golden_file" "$summary_file"
