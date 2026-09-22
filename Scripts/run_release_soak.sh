#!/usr/bin/env bash
# Preserve the real soak verdict, console output and a concise CI summary.
# An explicit command is accepted for failure-injection tests.
set -uo pipefail

log_root=${SWIFTTUI_SOAK_LOG_ROOT:-.build/release-soak}
mkdir -p "$log_root" || exit 1
if [[ $# -eq 0 ]]; then
  set -- sh ./Scripts/release_soundness_lane.sh --flaky-only
fi
status=0
"$@" 2>&1 | tee "$log_root/console.log" || status=$?
printf '%s\n' "$status" > "$log_root/exit-status.txt"

if [[ $status -eq 0 ]]; then
  verdict=PASS
else
  verdict=FAIL
  echo "::error title=Release runtime soak::Command failed (exit $status). Inspect the release-soak artifact for assertions, crashes, or watchdog diagnostics."
fi
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  {
    printf '### Release runtime soak: %s\n\n' "$verdict"
    printf 'Command exit status: `%s`. See the **release-soak** artifact for the console, launch logs and soundness traces.\n' "$status"
    if [[ $status -ne 0 ]]; then
      printf '\nThis failure blocks the workflow. Classify the recorded signature before attributing it to a historical flake.\n'
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$status"
