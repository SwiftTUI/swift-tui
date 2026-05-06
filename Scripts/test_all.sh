#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

write_full_log_report() {
  body_log=$1
  results_report=$2
  full_log_path=$3
  command_text=$4
  exit_code=$5

  generated_at=$(date '+%Y-%m-%d %H:%M:%S %z')
  marker_file=$(mktemp "/tmp/swift-tui-test-all-markers.XXXXXX")

  awk '
    /^==> / {
      title = substr($0, 5)
      if (!(title in seen)) {
        seen[title] = 1
        print title "|" NR
      }
    }
  ' "$body_log" >"$marker_file"

  result_count=$(awk 'END { print NR + 0 }' "$results_report" 2>/dev/null || echo 0)
  failure_count=$(awk -F '|' '$2 == "FAIL" { count += 1 } END { print count + 0 }' \
    "$results_report" 2>/dev/null || echo 0)
  line_offset=$((6 + result_count + failure_count + 2))

  {
    echo "swift-tui test log"
    echo "Generated: $generated_at"
    echo "Command: $command_text"
    echo "Exit status: $exit_code"
    echo ""
    echo "Sub-suite summary:"

    while IFS='|' read -r title status step_exit step_failures rerun_command log_file detail; do
      body_line=$(awk -F '|' -v title="$title" '$1 == title { print $2; exit }' "$marker_file")
      if [ -n "$body_line" ]; then
        report_line=$((line_offset + body_line))
      else
        report_line="?"
      fi

      printf '  %-4s  exit=%-3s  failures=%-3s  log=line %-5s  %s' \
        "$status" "$step_exit" "$step_failures" "$report_line" "$title"
      if [ "$status" = "SKIP" ] && [ -n "$detail" ]; then
        printf ' (%s)' "$detail"
      fi
      printf '\n'

      if [ "$status" = "FAIL" ]; then
        printf '        rerun: %s\n' "$rerun_command"
      fi
    done <"$results_report"

    echo ""
    echo "Raw run log:"
    cat "$body_log"
  } >"$full_log_path"

  rm -f "$marker_file"
}

if [ "${STUI_TEST_ALL_CAPTURED:-0}" != "1" ]; then
  timestamp=$(date '+%Y%m%d-%H%M%S')
  full_log_path="/tmp/swift-tui-test-all-$timestamp-$$.log"
  body_log=$(mktemp "/tmp/swift-tui-test-all-body.XXXXXX")
  status_file=$(mktemp "/tmp/swift-tui-test-all-status.XXXXXX")
  results_report=$(mktemp "/tmp/swift-tui-test-all-results.XXXXXX")
  command_text="sh $0"

  for argument; do
    command_text="$command_text $argument"
  done

  cleanup_capture() {
    rm -f "$body_log" "$status_file" "$results_report"
  }

  trap cleanup_capture EXIT

  : >"$full_log_path"
  : >"$results_report"

  export STUI_TEST_ALL_CAPTURED=1
  export STUI_TEST_ALL_FINAL_LOG=$full_log_path
  export STUI_TEST_ALL_RESULTS_REPORT=$results_report

  (
    set +e
    sh "$0" "$@"
    child_status=$?
    printf '%s\n' "$child_status" >"$status_file"
  ) 2>&1 | tee "$body_log"

  if [ -f "$status_file" ]; then
    captured_status=$(cat "$status_file")
  else
    captured_status=1
  fi

  write_full_log_report \
    "$body_log" \
    "$results_report" \
    "$full_log_path" \
    "$command_text" \
    "$captured_status"

  exit "$captured_status"
fi

skip_bun_install=0
host_os=$(uname -s)
is_linux=0
step_index=0

tmp_root=${TMPDIR:-/tmp}
log_root=$(mktemp -d "$tmp_root/swift-tui-test-all.XXXXXX")
results_file=$log_root/results.txt
any_failed=0

: >"$results_file"

cleanup() {
  if [ -n "${STUI_TEST_ALL_RESULTS_REPORT:-}" ] && [ -f "$results_file" ]; then
    cp "$results_file" "$STUI_TEST_ALL_RESULTS_REPORT" || true
  fi
  rm -rf "$log_root"
}

trap cleanup EXIT

if [ "$host_os" = "Linux" ]; then
  is_linux=1
  export DISABLE_EXPLICIT_PLATFORMS=1
fi

usage() {
  cat <<'EOF'
Usage: Scripts/test_all.sh [--skip-bun-install]

Runs the full checked-in repo verification surface:
  - checked-in policy hooks
  - accessibility guardrails for raw glyphs, color-state styling, and visual content
  - public-API baseline freshness check
  - root SwiftPM tests
  - Platforms/CLI tests
  - Platforms/Embedding tests
  - Platforms/WASI tests
  - Platforms/SwiftUI tests
  - Platforms/Web Bun tests
  - Examples/gallery tests
  - Examples/layouts tests
  - Examples/file-previewer tests
  - Tools/TermUIPerf tests
  - Examples/WebExample Bun tests
  - Examples/WebExample browser integration test

The script also checks required environment dependencies up front:
  - Swift 6.3.x via `swiftly` when available, otherwise `swift`
  - Bun availability
  - Bun workspace dependencies via `bun install --frozen-lockfile` at the repo root

On Linux, the script also:
  - exports `DISABLE_EXPLICIT_PLATFORMS=1` for repo package resolution
  - skips `Platforms/SwiftUI` tests because the SwiftUI host package is Apple-only

Pass --skip-bun-install to reuse the existing Bun install state.
EOF
}

record_result() {
  title=$1
  status=$2
  exit_code=$3
  failure_count=$4
  rerun_command=$5
  log_file=$6
  detail=$7

  printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "$title" "$status" "$exit_code" "$failure_count" "$rerun_command" "$log_file" "$detail" \
    >>"$results_file"
}

read_step_exit_code() {
  status_file=$1

  if [ -f "$status_file" ]; then
    cat "$status_file"
  else
    echo 1
  fi
}

run_logged_command() {
  log_file=$1
  status_file=$2
  shift 2

  rm -f "$status_file"

  (
    set +e
    "$@"
    command_status=$?
    printf '%s\n' "$command_status" >"$status_file"
    exit 0
  ) 2>&1 | tee "$log_file"

  command_status=$(read_step_exit_code "$status_file")
  [ "$command_status" -eq 0 ]
}

swift_command_text() {
  if [ "$is_linux" -eq 1 ]; then
    printf 'DISABLE_EXPLICIT_PLATFORMS=1 '
  fi

  if [ "$SWIFT_LAUNCHER" = "swiftly" ]; then
    printf 'swiftly run swift'
  else
    printf 'swift'
  fi

  for argument; do
    printf ' %s' "$argument"
  done
}

derive_failure_count() {
  log_file=$1

  if [ ! -f "$log_file" ]; then
    echo "?"
    return
  fi

  count=$(
    awk '
      function first_number(text) {
        if (match(text, /[0-9]+/)) {
          return substr(text, RSTART, RLENGTH)
        }
        return ""
      }

      {
        line = tolower($0)

        if (match(line, /[0-9]+[[:space:]]+tests?[[:space:]]+failed/)) {
          candidate = first_number(substr(line, RSTART, RLENGTH))
        }
        if (match(line, /with[[:space:]]+[0-9]+[[:space:]]+(failure|failures|issue|issues)/)) {
          candidate = first_number(substr(line, RSTART, RLENGTH))
        }
        if (match(line, /[0-9]+[[:space:]]+(failure|failures)/)) {
          candidate = first_number(substr(line, RSTART, RLENGTH))
        }
        if (match(line, /[0-9]+[[:space:]]+fail/)) {
          candidate = first_number(substr(line, RSTART, RLENGTH))
        }
        if (match(line, /(fail|failed):[[:space:]]+[0-9]+/)) {
          candidate = first_number(substr(line, RSTART, RLENGTH))
        }
      }

      END {
        if (candidate != "" && candidate != "0") {
          print candidate
        }
      }
    ' "$log_file"
  )

  if [ -n "$count" ]; then
    echo "$count"
  else
    echo "?"
  fi
}

for argument in "$@"; do
  case "$argument" in
  --skip-bun-install)
    skip_bun_install=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    >&2 echo "Unknown argument: $argument"
    >&2 echo ""
    usage
    exit 1
    ;;
  esac
done

SWIFT_LAUNCHER=""

detect_swift_command() {
  if command -v swiftly >/dev/null 2>&1; then
    SWIFT_LAUNCHER=swiftly
    return 0
  fi

  if command -v swift >/dev/null 2>&1; then
    SWIFT_LAUNCHER=swift
    return 0
  fi

  >&2 echo "Missing required command: swiftly or swift"
  exit 1
}

run_swift() {
  if [ "$SWIFT_LAUNCHER" = "swiftly" ]; then
    swiftly run swift "$@"
  else
    swift "$@"
  fi
}

require_command() {
  name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    >&2 echo "Missing required command: $name"
    exit 1
  fi
}

run_step() {
  title=$1
  workdir=$2
  rerun_command=$3
  shift 3
  step_index=$((step_index + 1))
  log_file=$log_root/step-$step_index.log
  status_file=$log_root/step-$step_index.status

  echo ""
  echo "==> $title"

  if (
    cd "$workdir" &&
      run_logged_command "$log_file" "$status_file" "$@"
  ); then
    rm -f "$status_file"
    echo "PASS: $title"
    record_result "$title" "PASS" "0" "-" "$rerun_command" "$log_file" ""
  else
    exit_code=$(read_step_exit_code "$status_file")
    rm -f "$status_file"
    failure_count=$(derive_failure_count "$log_file")
    >&2 echo "FAIL: $title"
    any_failed=1
    record_result "$title" "FAIL" "$exit_code" "$failure_count" "$rerun_command" "$log_file" ""
  fi
}

run_function_step() {
  title=$1
  rerun_command=$2
  shift 2
  step_index=$((step_index + 1))
  log_file=$log_root/step-$step_index.log
  status_file=$log_root/step-$step_index.status

  echo ""
  echo "==> $title"

  if run_logged_command "$log_file" "$status_file" "$@"; then
    rm -f "$status_file"
    echo "PASS: $title"
    record_result "$title" "PASS" "0" "-" "$rerun_command" "$log_file" ""
  else
    exit_code=$(read_step_exit_code "$status_file")
    rm -f "$status_file"
    failure_count=$(derive_failure_count "$log_file")
    >&2 echo "FAIL: $title"
    any_failed=1
    record_result "$title" "FAIL" "$exit_code" "$failure_count" "$rerun_command" "$log_file" ""
  fi
}

skip_step() {
  title=$1
  reason=$2

  echo ""
  echo "==> $title"
  echo "SKIP: $title ($reason)"
  record_result "$title" "SKIP" "-" "-" "-" "" "$reason"
}

check_swift_environment() {
  version_output=$(run_swift --version 2>&1)
  echo "$version_output"

  case "$version_output" in
  *"Swift version 6.3"* | *"Apple Swift version 6.3"*)
    return 0
    ;;
  *)
    >&2 echo ""
    >&2 echo "Expected Swift 6.3.x for this repository."
    >&2 echo "Use 'swiftly run swift ...' directly, or make sure 'swift' resolves to the swiftly-managed toolchain."
    return 1
    ;;
  esac
}

check_bun_environment() {
  bun --version
}

print_failure_logs() {
  while IFS='|' read -r title status exit_code failure_count rerun_command log_file detail; do
    [ "$status" = "FAIL" ] || continue

    >&2 echo ""
    >&2 echo "===== $title (exit $exit_code) ====="
    if [ -f "$log_file" ]; then
      cat "$log_file" >&2
    else
      >&2 echo "Missing captured log: $log_file"
    fi
  done <"$results_file"
}

print_summary() {
  echo ""
  echo "Repo test summary:"

  while IFS='|' read -r title status exit_code failure_count rerun_command log_file detail; do
    case "$status" in
    PASS)
      printf '  %-4s  exit=%-3s  failures=%-3s  %s\n' \
        "$status" "$exit_code" "$failure_count" "$title"
      ;;
    FAIL)
      printf '  %-4s  exit=%-3s  failures=%-3s  %s\n' \
        "$status" "$exit_code" "$failure_count" "$title"
      printf '        rerun: %s\n' "$rerun_command"
      ;;
    SKIP)
      printf '  %-4s  exit=%-3s  failures=%-3s  %s' \
        "$status" "$exit_code" "$failure_count" "$title"
      if [ -n "$detail" ]; then
        printf ' (%s)' "$detail"
      fi
      printf '\n'
      ;;
    esac
  done <"$results_file"

  if [ -n "${STUI_TEST_ALL_FINAL_LOG:-}" ]; then
    echo "Full log: $STUI_TEST_ALL_FINAL_LOG"
  fi

  if [ "$any_failed" -eq 0 ]; then
    echo "Result: PASS"
  else
    echo "Result: FAIL"
  fi
}

detect_swift_command
require_command bun

if [ "$is_linux" -eq 1 ]; then
  echo "Linux host detected; exporting DISABLE_EXPLICIT_PLATFORMS=1 and skipping Apple-only SwiftUI host tests."
fi

swift_version_command=$(swift_command_text --version)

run_function_step \
  "Check Swift toolchain" \
  "$swift_version_command" \
  check_swift_environment

run_function_step \
  "Check Bun availability" \
  "bun --version" \
  check_bun_environment

if [ -f "$repo_root/package.json" ] && [ -f "$repo_root/bun.lock" ] && [ "$skip_bun_install" -eq 0 ]; then
  run_step \
    "Install Bun workspace dependencies" \
    "$repo_root" \
    "bun install --frozen-lockfile" \
    bun install --frozen-lockfile
fi

run_step \
  "Check public-surface policies" \
  "$repo_root" \
  "./Scripts/check_public_surface_policies.sh" \
  ./Scripts/check_public_surface_policies.sh

run_step \
  "Check concurrency-safety policies" \
  "$repo_root" \
  "./Scripts/check_concurrency_safety_policies.sh" \
  ./Scripts/check_concurrency_safety_policies.sh

run_step \
  "Check accessibility guardrails" \
  "$repo_root" \
  "./Scripts/check_accessibility_guardrails.sh" \
  ./Scripts/check_accessibility_guardrails.sh

run_step \
  "Check public-API baseline" \
  "$repo_root" \
  "./Scripts/generate_public_api_inventory.sh --check" \
  ./Scripts/generate_public_api_inventory.sh --check

run_function_step \
  "Run root SwiftPM tests" \
  "$(swift_command_text test)" \
  run_swift test

run_function_step \
  "Run Platforms/CLI tests" \
  "$(swift_command_text test --package-path Platforms/CLI)" \
  run_swift test --package-path Platforms/CLI

run_function_step \
  "Run Platforms/Embedding tests" \
  "$(swift_command_text test --package-path Platforms/Embedding)" \
  run_swift test --package-path Platforms/Embedding

run_function_step \
  "Run Platforms/WASI tests" \
  "$(swift_command_text test --package-path Platforms/WASI)" \
  run_swift test --package-path Platforms/WASI

if [ "$is_linux" -eq 1 ]; then
  skip_step \
    "Run Platforms/SwiftUI tests" \
    "SwiftUI host package is only available on Apple platforms"
else
  run_function_step \
    "Run Platforms/SwiftUI tests" \
    "$(swift_command_text test --package-path Platforms/SwiftUI)" \
    run_swift test --package-path Platforms/SwiftUI
fi

#run_step \
#  "Run Platforms/Web Bun tests" \
#  "$repo_root/Platforms/Web" \
#  "cd Platforms/Web && bun test" \
#  bun test

run_function_step \
  "Run Examples/gallery tests" \
  "$(swift_command_text test --package-path Examples/gallery)" \
  run_swift test --package-path Examples/gallery

run_function_step \
  "Run Examples/layouts tests" \
  "$(swift_command_text test --package-path Examples/layouts)" \
  run_swift test --package-path Examples/layouts

run_function_step \
  "Run Examples/file-previewer tests" \
  "$(swift_command_text test --package-path Examples/file-previewer)" \
  run_swift test --package-path Examples/file-previewer

run_function_step \
  "Run Tools/TermUIPerf tests" \
  "$(swift_command_text test --package-path Tools/TermUIPerf)" \
  run_swift test --package-path Tools/TermUIPerf

# run_step \
#   "Run Examples/WebExample Bun tests" \
#   "$repo_root/Examples/WebExample" \
#   "cd Examples/WebExample && bun test" \
#   bun test
#
# run_step \
#   "Run Examples/WebExample browser integration test" \
#   "$repo_root/Examples/WebExample" \
#   "cd Examples/WebExample && bun run test:browser" \
#   bun run test:browser

if [ "$any_failed" -eq 0 ]; then
  print_summary
  exit 0
fi

>&2 echo ""
>&2 echo "Failure logs:"
print_failure_logs
print_summary >&2

exit 1
