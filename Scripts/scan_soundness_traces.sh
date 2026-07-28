#!/usr/bin/env sh

set -eu
set -f

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
trace_root=${1:-"$repo_root/.build/soundness-trace"}
quarantine_file=${2:-"$script_dir/soundness_quarantine.txt"}

if [ "$#" -gt 2 ]; then
  >&2 echo "Usage: $0 [trace-root [quarantine-file]]"
  exit 2
fi

if [ ! -f "$quarantine_file" ]; then
  >&2 echo "FAIL: soundness quarantine ledger not found: $quarantine_file"
  exit 2
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-soundness-scan.XXXXXX")
entries_file=$scratch/entries.tsv
ledger_file=$scratch/ledger.tsv
trace_files=$scratch/trace-files.txt
kinds_file=$scratch/kinds.txt

cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

: >"$entries_file"
: >"$ledger_file"
: >"$trace_files"

line_number=0
while IFS= read -r ledger_line || [ -n "$ledger_line" ]; do
  line_number=$((line_number + 1))
  case "$ledger_line" in
  "" | \#*) continue ;;
  esac

  # Intentional splitting: the ledger contract is
  # <kind> <YYYY-MM-DD> <tracking-ref> <reason containing count=N>.
  # shellcheck disable=SC2086
  set -- $ledger_line
  if [ "$#" -lt 4 ]; then
    >&2 echo "FAIL: invalid quarantine ledger row $quarantine_file:$line_number"
    exit 2
  fi

  kind=$1
  date=$2
  tracking_ref=$3
  shift 3
  reason=$*
  baseline=""

  case "$kind" in
  *[!a-z-]* | "")
    >&2 echo "FAIL: invalid soundness kind '$kind' at $quarantine_file:$line_number"
    exit 2
    ;;
  esac

  for token; do
    case "$token" in
    count=*)
      if [ -n "$baseline" ]; then
        >&2 echo "FAIL: duplicate count token for '$kind' at $quarantine_file:$line_number"
        exit 2
      fi
      baseline=${token#count=}
      ;;
    esac
  done

  case "$baseline" in
  "" | *[!0-9]*)
    >&2 echo "FAIL: '$kind' needs one integer count=N token at $quarantine_file:$line_number"
    exit 2
    ;;
  esac

  if awk -F '\t' -v candidate="$kind" '$1 == candidate { found = 1 } END { exit !found }' \
    "$ledger_file"; then
    >&2 echo "FAIL: duplicate quarantine kind '$kind' at $quarantine_file:$line_number"
    exit 2
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$kind" "$baseline" "$date" "$tracking_ref" "$reason" >>"$ledger_file"
done <"$quarantine_file"

if [ -d "$trace_root" ]; then
  find "$trace_root" -type f -name '*.log' -print | LC_ALL=C sort >"$trace_files"
fi

while IFS= read -r trace_file; do
  source_name=${trace_file#"$trace_root"/}
  awk -v source="$source_name" '
    /^\[SOUNDNESS\] [a-z-]+:/ {
      kind = $0
      sub(/^\[SOUNDNESS\] /, "", kind)
      sub(/:.*/, "", kind)
      printf "%s\t%s\t%s\n", kind, source, $0
    }
  ' "$trace_file" >>"$entries_file"
done <"$trace_files"

awk -F '\t' '{ print $1 }' "$entries_file" "$ledger_file" | LC_ALL=C sort -u >"$kinds_file"

print_kind_lines() {
  printed_kind=$1
  awk -F '\t' -v kind="$printed_kind" '
    $1 == kind {
      print "  " $2 ": " $3
    }
  ' "$entries_file"
}

failed=0
while IFS= read -r kind; do
  [ -n "$kind" ] || continue
  actual=$(
    awk -F '\t' -v candidate="$kind" '
      $1 == candidate { count += 1 }
      END { print count + 0 }
    ' "$entries_file"
  )
  baseline=$(
    awk -F '\t' -v candidate="$kind" '
      $1 == candidate { print $2; exit }
    ' "$ledger_file"
  )

  if [ -z "$baseline" ]; then
    if [ "$actual" -gt 0 ]; then
      echo "FAIL: $kind count=$actual is not quarantined"
      print_kind_lines "$kind"
      failed=1
    fi
    continue
  fi

  if [ "$actual" -gt "$baseline" ]; then
    echo "FAIL: $kind count=$actual exceeds baseline=$baseline"
    print_kind_lines "$kind"
    failed=1
  elif [ "$actual" -eq "$baseline" ]; then
    echo "WARNING: $kind count=$actual matches baseline=$baseline"
    print_kind_lines "$kind"
  else
    echo "WARNING: $kind count=$actual is below baseline=$baseline; reduce the ledger"
    print_kind_lines "$kind"
  fi
done <"$kinds_file"

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "PASS: soundness trace counts are within their exact quarantine baselines"
