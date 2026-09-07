#!/usr/bin/env sh

# Result records shared by the gate and its captured full-log report.
# Text fields use a fixed prefix followed by POSIX \0ddd byte escapes. Records
# therefore stay on one line even when command/detail text contains pipes,
# tabs, literal backslashes, or newlines. Status and numeric fields stay plain.
# Readers publish the same field variables used by the gate's report helpers.

repo_result_encode_field() {
  printf '@'
  printf '%s' "$1" |
    LC_ALL=C od -An -v -to1 |
    awk '{ for (i = 1; i <= NF; i++) printf "\\0%s", $i }'
}

read_repo_result_record() {
  IFS='|' read -r encoded_title status exit_code failure_count encoded_command encoded_log encoded_detail ||
    return 1

  # A suffix keeps command substitution from stripping payload newlines.
  # printf decodes the byte escapes once; a decoded literal \c is not reparsed.
  title=$(printf '%b_' "${encoded_title#@}")
  title=${title%_}
  rerun_command=$(printf '%b_' "${encoded_command#@}")
  rerun_command=${rerun_command%_}
  log_file=$(printf '%b_' "${encoded_log#@}")
  log_file=${log_file%_}
  detail=$(printf '%b_' "${encoded_detail#@}")
  detail=${detail%_}
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
    "$(repo_result_encode_field "$title")" "$status" "$exit_code" "$failure_count" \
    "$(repo_result_encode_field "$rerun_command")" \
    "$(repo_result_encode_field "$log_file")" \
    "$(repo_result_encode_field "$detail")" >>"$results_file"
}

print_failure_logs() {
  while read_repo_result_record; do
    [ "$status" = "FAIL" ] || [ "$status" = "TIMEOUT" ] || continue

    >&2 echo ""
    printf '===== %s (exit %s) =====\n' "$title" "$exit_code" >&2
    if [ -f "$log_file" ]; then
      cat "$log_file" >&2
    else
      printf 'Missing captured log: %s\n' "$log_file" >&2
    fi
  done <"$results_file"
}

print_summary() {
  echo ""
  echo "Repo test summary:"

  while read_repo_result_record; do
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
    TIMEOUT)
      printf '  %-4s  exit=%-3s  failures=%-3s  %s' \
        "$status" "$exit_code" "$failure_count" "$title"
      if [ -n "$detail" ]; then
        printf ' (%s)' "$detail"
      fi
      printf '\n'
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

  if [ -n "${SWIFTTUI_TEST_ALL_FINAL_LOG:-}" ]; then
    printf 'Full log: %s\n' "$SWIFTTUI_TEST_ALL_FINAL_LOG"
  fi

  if [ "$any_failed" -eq 0 ]; then
    echo "Result: PASS"
  else
    echo "Result: FAIL"
  fi
}

print_full_log_step_summary() {
  summary_line_offset=$1
  while read_repo_result_record; do
    body_line=$(SWIFTTUI_RESULT_TITLE="$title" awk '
      {
        separator = index($0, "|")
        if (substr($0, separator + 1) == ENVIRON["SWIFTTUI_RESULT_TITLE"]) {
          print substr($0, 1, separator - 1)
          exit
        }
      }
    ' "$marker_file")
    if [ -n "$body_line" ]; then
      report_line=$((summary_line_offset + body_line))
    else
      report_line="?"
    fi

    printf '  %-4s  exit=%-3s  failures=%-3s  log=line %-5s  %s' \
      "$status" "$exit_code" "$failure_count" "$report_line" "$title"
    if [ "$status" = "SKIP" ] && [ -n "$detail" ]; then
      printf ' (%s)' "$detail"
    fi
    if [ "$status" = "TIMEOUT" ] && [ -n "$detail" ]; then
      printf ' (%s)' "$detail"
    fi
    printf '\n'

    if [ "$status" = "FAIL" ] || [ "$status" = "TIMEOUT" ]; then
      printf '        rerun: %s\n' "$rerun_command"
    fi
  done <"$results_report"
}

write_full_log_report() {
  body_log=$1
  results_report=$2
  full_log_path=$3
  command_text=$4
  exit_code=$5

  generated_at=$(date '+%Y-%m-%d %H:%M:%S %z')
  marker_file=$(mktemp "/tmp/swift-tui-$runner_name-markers.XXXXXX")
  header_file=$(mktemp "/tmp/swift-tui-$runner_name-header.XXXXXX")

  awk '
    /^==> / {
      title = substr($0, 5)
      if (!(title in seen)) {
        seen[title] = 1
        print NR "|" title
      }
    }
  ' "$body_log" >"$marker_file"

  {
    echo "swift-tui test log"
    printf 'Generated: %s\n' "$generated_at"
    printf 'Command: %s\n' "$command_text"
    printf 'Exit status: %s\n' "$exit_code"
    echo ""
    echo "Sub-suite summary:"
  } >"$header_file"

  # Count rendered lines before command substitution can strip trailing
  # newlines. A multiline rerun or timeout detail must not skew log links.
  header_lines=$(awk 'END { print NR + 0 }' "$header_file")
  summary_lines=$(print_full_log_step_summary 0 | awk 'END { print NR + 0 }')
  line_offset=$((header_lines + summary_lines + 2))

  {
    cat "$header_file"
    print_full_log_step_summary "$line_offset"
    echo ""
    echo "Raw run log:"
    cat "$body_log"
  } >"$full_log_path"

  rm -f "$marker_file" "$header_file"
}
