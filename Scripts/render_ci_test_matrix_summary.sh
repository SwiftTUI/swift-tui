#!/usr/bin/env sh

set -eu

usage() {
  cat <<'EOF'
Usage: Scripts/render_ci_test_matrix_summary.sh EXPECTED_FILE RESULTS_DIR OUTPUT_FILE

EXPECTED_FILE rows:
  id|lane|platform|arch|runner|command

RESULTS_DIR contains one optional result file per expected id:
  <id>.result

Each result file contains:
  id|result

The output is a GitHub-flavored Markdown matrix summary.
EOF
}

if [ "$#" -ne 3 ]; then
  usage >&2
  exit 2
fi

expected_file=$1
results_dir=$2
output_file=$3

if [ ! -f "$expected_file" ]; then
  >&2 echo "Missing expected matrix file: $expected_file"
  exit 1
fi

if [ ! -d "$results_dir" ]; then
  mkdir -p "$results_dir"
fi

escape_cell() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}

append_count() {
  count=$1
  label=$2

  [ "$count" -gt 0 ] || return 0

  if [ -z "$count_text" ]; then
    count_text="$count $label"
  else
    count_text="$count_text, $count $label"
  fi
}

total_count=0
success_count=0
failure_count=0
cancelled_count=0
skipped_count=0
missing_count=0
other_count=0

{
  echo "## CI Test Matrix"
  echo ""
  echo "| Lane | Platform | Arch | Runner | Result | Command |"
  echo "| --- | --- | --- | --- | --- | --- |"

  while IFS='|' read -r id lane platform arch runner command; do
    case "$id" in
    "" | \#*)
      continue
      ;;
    esac

    total_count=$((total_count + 1))
    result=missing
    result_file=$results_dir/$id.result

    if [ -f "$result_file" ]; then
      IFS='|' read -r result_id recorded_result <"$result_file" || true
      if [ "$result_id" = "$id" ] && [ -n "$recorded_result" ]; then
        result=$recorded_result
      fi
    fi

    case "$result" in
    success)
      success_count=$((success_count + 1))
      ;;
    failure)
      failure_count=$((failure_count + 1))
      ;;
    cancelled)
      cancelled_count=$((cancelled_count + 1))
      ;;
    skipped)
      skipped_count=$((skipped_count + 1))
      ;;
    missing)
      missing_count=$((missing_count + 1))
      ;;
    *)
      other_count=$((other_count + 1))
      ;;
    esac

    printf '| %s | %s | %s | %s | %s | `%s` |\n' \
      "$(escape_cell "$lane")" \
      "$(escape_cell "$platform")" \
      "$(escape_cell "$arch")" \
      "$(escape_cell "$runner")" \
      "$(escape_cell "$result")" \
      "$command"
  done <"$expected_file"

  if [ "$total_count" -eq 0 ]; then
    >&2 echo "Expected matrix file contains no lanes: $expected_file"
    exit 1
  fi

  count_text=""
  append_count "$success_count" success
  append_count "$failure_count" failure
  append_count "$cancelled_count" cancelled
  append_count "$skipped_count" skipped
  append_count "$missing_count" missing
  append_count "$other_count" other

  overall_result=success
  if [ "$success_count" -ne "$total_count" ]; then
    overall_result=failure
  fi

  echo ""
  printf 'Overall result: %s (%s)\n' "$overall_result" "$count_text"

  if [ "$missing_count" -gt 0 ]; then
    echo ""
    echo "Missing result artifacts mean the lane did not publish a status record before the summary job ran."
  fi
} >"$output_file"
