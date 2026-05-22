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
linux-amd64|Linux repo gate|Linux|amd64|ubuntu-24.04|sh ./Scripts/test_gate.sh --skip-bun-install
linux-arm64|Linux repo gate|Linux|arm64|ubuntu-24.04-arm|sh ./Scripts/test_gate.sh --skip-bun-install
macos|macOS repo gate|macOS|-|macos-26|sh ./Scripts/test_gate.sh --skip-bun-install
ios|iOS package build|iOS|generic|macos-26|xcodebuild -scheme SwiftUIHost -destination generic/platform=iOS -skipPackagePluginValidation build
EOF

cat >"$results_dir/linux-amd64.result" <<'EOF'
linux-amd64|success
EOF

cat >"$results_dir/linux-arm64.result" <<'EOF'
linux-arm64|failure
EOF

cat >"$results_dir/macos.result" <<'EOF'
macos|success
EOF

cat >"$golden_file" <<'EOF'
## CI Test Matrix

| Lane | Platform | Arch | Runner | Result | Command |
| --- | --- | --- | --- | --- | --- |
| Linux repo gate | Linux | amd64 | ubuntu-24.04 | success | `sh ./Scripts/test_gate.sh --skip-bun-install` |
| Linux repo gate | Linux | arm64 | ubuntu-24.04-arm | failure | `sh ./Scripts/test_gate.sh --skip-bun-install` |
| macOS repo gate | macOS | - | macos-26 | success | `sh ./Scripts/test_gate.sh --skip-bun-install` |
| iOS package build | iOS | generic | macos-26 | missing | `xcodebuild -scheme SwiftUIHost -destination generic/platform=iOS -skipPackagePluginValidation build` |

Overall result: failure (2 success, 1 failure, 1 missing)

Missing result artifacts mean the lane did not publish a status record before the summary job ran.
EOF

"$repo_root/Scripts/render_ci_test_matrix_summary.sh" \
  "$expected_file" \
  "$results_dir" \
  "$summary_file"

diff -u "$golden_file" "$summary_file"
