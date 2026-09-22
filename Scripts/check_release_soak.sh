#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd -- "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
for expected in 0 1 143; do
  status=0
  SWIFTTUI_SOAK_LOG_ROOT="$scratch/$expected" GITHUB_STEP_SUMMARY="$scratch/summary-$expected.md" \
    bash "$repo_root/Scripts/run_release_soak.sh" \
    sh -c 'echo "fixture stdout"; echo "fixture stderr" >&2; exit "$1"' sh "$expected" \
    > "$scratch/output-$expected" 2>&1 || status=$?
  [[ $status -eq $expected ]]
  [[ $(cat "$scratch/$expected/exit-status.txt") -eq $expected ]]
  rg -q 'fixture stdout' "$scratch/$expected/console.log"
  rg -q 'fixture stderr' "$scratch/$expected/console.log"
  if [[ $expected -eq 0 ]]; then
    rg -q 'soak: PASS' "$scratch/summary-$expected.md"
    ! rg -q '::error' "$scratch/output-$expected"
  else
    rg -q 'soak: FAIL' "$scratch/summary-$expected.md"
    rg -q '::error' "$scratch/output-$expected"
  fi
done
echo 'PASS: release soak preserves success, assertion failure and termination verdicts with logs'
