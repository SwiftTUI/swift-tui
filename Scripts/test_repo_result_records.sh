#!/usr/bin/env sh
set -eu

script_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$script_root/lib/repo_result_records.sh"

fixture_root=$(mktemp -d /tmp/swift-tui-result-records.XXXXXX)
trap 'rm -rf "$fixture_root"' EXIT
results_file=$fixture_root/results
: >"$results_file"
runner_name=result-record-fixture
unset SWIFTTUI_TEST_ALL_FINAL_LOG

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_same() {
  [ "$1" = "$2" ] || fail "$3"
}

require_record() {
  read_repo_result_record || fail "missing result record"
}

fixture_title=$(printf 'runtime | C "quotes" \\c café\t字')
fixture_command=$(cat <<'COMMAND'
swiftly run swift test --filter 'A|NavigationPresentation|B'
literal \c \n \\ $(exit 99) "quotes" café	字

_
COMMAND
)
fixture_command=${fixture_command%_}
fixture_detail=$(cat <<'DETAIL'
timeout | detail	"quoted" \c café
second line

_
DETAIL
)
fixture_detail=${fixture_detail%_}
fixture_log="$fixture_root/failure | café
tail.log"
fixture_timeout_log=$fixture_root/timeout.log
printf 'captured failure marker\n' >"$fixture_log"
printf 'captured timeout marker\n' >"$fixture_timeout_log"

record_result "$fixture_title" FAIL 7 17 "$fixture_command" "$fixture_log" ''
record_result 'next record' PASS 0 - 'plain command' '' ''
record_result 'timeout|record' TIMEOUT 124 - "$fixture_command" "$fixture_timeout_log" "$fixture_detail"
record_result 'skip record' SKIP - - - '' "$fixture_detail"
record_result '' PASS 0 - '' '' ''

assert_same "$(awk 'END { print NR }' "$results_file")" 5 "records must remain single-line"
awk -F '|' 'NF != 7 { exit 1 }' "$results_file" || fail "record fields shifted"
assert_same "$(awk -F '|' '$2 == "FAIL" || $2 == "TIMEOUT" { n++ } END { print n }' "$results_file")" \
  2 "failure status accounting changed"

{
  require_record
  assert_same "$title" "$fixture_title" "title bytes changed"
  assert_same "$status:$exit_code:$failure_count" FAIL:7:17 "failure status fields changed"
  assert_same "$rerun_command" "$fixture_command" "command bytes or trailing newlines changed"
  assert_same "$log_file" "$fixture_log" "log path bytes changed"
  assert_same "$detail" '' "empty detail shifted"
  require_record
  assert_same "$title:$status:$exit_code:$failure_count" 'next record:PASS:0:-' "next record shifted"
  assert_same "$rerun_command:$log_file:$detail" 'plain command::' "empty fields shifted"
  require_record
  assert_same "$title:$status:$exit_code:$failure_count" 'timeout|record:TIMEOUT:124:-' "timeout changed"
  assert_same "$rerun_command" "$fixture_command" "timeout command changed"
  assert_same "$log_file" "$fixture_timeout_log" "timeout path changed"
  assert_same "$detail" "$fixture_detail" "detail bytes or trailing newlines changed"
  require_record
  assert_same "$title:$status:$exit_code:$failure_count" 'skip record:SKIP:-:-' "skip changed"
  assert_same "$detail" "$fixture_detail" "skip detail changed"
  require_record
  assert_same "$title:$status:$exit_code:$failure_count:$rerun_command:$log_file:$detail" \
    ':PASS:0:-:::' "empty text fields changed"
  if read_repo_result_record; then fail "unexpected extra record"; fi
} <"$results_file"

print_failure_logs 2>"$fixture_root/failures"
{
  printf '\n===== %s (exit 7) =====\n' "$fixture_title"
  cat "$fixture_log"
  printf '\n===== timeout|record (exit 124) =====\n'
  cat "$fixture_timeout_log"
} >"$fixture_root/expected-failures"
cmp -s "$fixture_root/failures" "$fixture_root/expected-failures" ||
  fail "failure reader lost a command-delimited log path or literal backslash"

any_failed=1
print_summary >"$fixture_root/summary"
{
  printf '\nRepo test summary:\n'
  printf '  %-4s  exit=%-3s  failures=%-3s  %s\n' FAIL 7 17 "$fixture_title"
  printf '        rerun: %s\n' "$fixture_command"
  printf '  %-4s  exit=%-3s  failures=%-3s  %s\n' PASS 0 - 'next record'
  printf '  %-4s  exit=%-3s  failures=%-3s  %s (%s)\n' TIMEOUT 124 - 'timeout|record' "$fixture_detail"
  printf '        rerun: %s\n' "$fixture_command"
  printf '  %-4s  exit=%-3s  failures=%-3s  %s (%s)\n' SKIP - - 'skip record' "$fixture_detail"
  printf '  %-4s  exit=%-3s  failures=%-3s  %s\n' PASS 0 - ''
  printf 'Result: FAIL\n'
} >"$fixture_root/expected-summary"
cmp -s "$fixture_root/summary" "$fixture_root/expected-summary" ||
  fail "summary reader changed fields or failure status"
assert_same "$any_failed" 1 "reporting changed aggregate failure state"

fixture_body=$fixture_root/body
{
  for fixture_marker in "$fixture_title" 'next record' 'timeout|record' 'skip record' ''; do
    printf '==> %s\nbody output\n' "$fixture_marker"
  done
} >"$fixture_body"
fixture_report=$fixture_root/full.log
write_full_log_report "$fixture_body" "$results_file" "$fixture_report" 'sh gate \c "quoted"' 7
grep -Fxq 'Exit status: 7' "$fixture_report" || fail "full report changed process exit"
grep -Fxq 'Command: sh gate \c "quoted"' "$fixture_report" || fail "top-level command changed"
awk '
  { lines[NR] = $0 }
  END {
    for (i = 1; i <= NR; i++) {
      if (match(lines[i], /log=line [0-9]+/)) {
        number = substr(lines[i], RSTART + 9, RLENGTH - 9) + 0
        if (lines[number] !~ /^==> /) exit 1
        links++
      }
    }
    if (links != 5) exit 1
  }
' "$fixture_report" || fail "full report links do not land on all five step headers"
awk '/^Raw run log:$/ { body = 1; next } body { print }' "$fixture_report" >"$fixture_root/raw-body"
cmp -s "$fixture_body" "$fixture_root/raw-body" || fail "full report changed the raw log"

# Compare full-report metadata to the ordinary summary after removing only
# its extra log-link column. Both readers must retain the same byte payloads.
awk '
  /^Sub-suite summary:$/ { summary = 1; next }
  /^Raw run log:$/ { exit }
  summary { sub(/  log=line [0-9?]+ +/, "  "); print }
' "$fixture_report" >"$fixture_root/full-summary"
sed '1,2d; $d' "$fixture_root/expected-summary" >"$fixture_root/summary-fields"
printf '\n' >>"$fixture_root/summary-fields"
cmp -s "$fixture_root/full-summary" "$fixture_root/summary-fields" ||
  fail "full report reader changed metadata"

printf 'PASS: result records round-trip five consecutive records; all three report readers preserve metadata and accounting\n'
