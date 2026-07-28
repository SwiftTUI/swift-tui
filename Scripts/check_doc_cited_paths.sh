#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exceptions_file="$repo_root/Scripts/data/doc_cited_path_exceptions.txt"

usage() {
  cat <<'EOF'
Usage: Scripts/check_doc_cited_paths.sh [--self-test|--print-current]

Checks stable documentation for cited repository paths that do not exist and
for retired architecture claims. The checked-in exception ledger is exact:
new violations and stale exception rows both fail.
EOF
}

collect_scan_files() {
  csf_scan_root=$1
  csf_output_file=$2
  csf_unsorted_file="${csf_output_file}.unsorted"

  (
    cd "$csf_scan_root"
    if [ -f README.md ]; then
      printf '%s\n' README.md
    fi
    if [ -d docs ]; then
      find docs -maxdepth 1 -type f -name '*.md' ! -name CHANGELOG.md -print
    fi
    for catalog_root in Sources Platforms Tests; do
      if [ -d "$catalog_root" ]; then
        find "$catalog_root" -type f -path '*.docc/*.md' -print
      fi
    done
  ) >"$csf_unsorted_file"
  LC_ALL=C sort -u "$csf_unsorted_file" >"$csf_output_file"
  rm -f "$csf_unsorted_file"
}

normalize_cited_path() {
  printf '%s\n' "$1" |
    sed -E \
      -e 's/:[0-9]+(-[0-9]+)?$//' \
      -e 's/[.,;:!?]+$//'
}

record_cited_path_violations() {
  rcp_scan_root=$1
  rcp_files_file=$2
  rcp_output_file=$3
  rcp_matches_file="${rcp_output_file}.matches"

  : >"$rcp_output_file"
  while IFS= read -r rcp_source_file; do
    [ -n "$rcp_source_file" ] || continue
    if rg -o --no-line-number \
      '\b(Sources|Platforms|Tests|Scripts|Tools)/[A-Za-z0-9_@+./-]+(:[0-9]+(-[0-9]+)?)?' \
      "$rcp_scan_root/$rcp_source_file" >"$rcp_matches_file"
    then
      :
    else
      rcp_status=$?
      if [ "$rcp_status" -ne 1 ]; then
        >&2 printf 'Path extraction failed for %s\n' "$rcp_source_file"
        return "$rcp_status"
      fi
    fi

    while IFS= read -r raw_path; do
      cited_path=$(normalize_cited_path "$raw_path")
      [ -n "$cited_path" ] || continue
      case "$cited_path" in
      */)
        if [ ! -d "$rcp_scan_root/$cited_path" ]; then
          printf 'missing-path|%s|%s\n' "$rcp_source_file" "$cited_path"
        fi
        ;;
      *)
        if [ ! -e "$rcp_scan_root/$cited_path" ]; then
          printf 'missing-path|%s|%s\n' "$rcp_source_file" "$cited_path"
        fi
        ;;
      esac
    done <"$rcp_matches_file"
  done <"$rcp_files_file" >>"$rcp_output_file"
  rm -f "$rcp_matches_file"
}

record_forbidden_pattern() {
  rfp_scan_root=$1
  rfp_files_file=$2
  rfp_output_file=$3
  rfp_rule_id=$4
  rfp_allowed_file=$5
  rfp_pattern=$6
  rfp_multiline=$7
  rfp_ignore_case=$8

  while IFS= read -r rfp_source_file; do
    [ -n "$rfp_source_file" ] || continue
    if [ -n "$rfp_allowed_file" ] && [ "$rfp_source_file" = "$rfp_allowed_file" ]; then
      continue
    fi

    set -- rg -q
    if [ "$rfp_multiline" = 1 ]; then
      set -- "$@" -U
    fi
    if [ "$rfp_ignore_case" = 1 ]; then
      set -- "$@" -i
    fi
    set -- "$@" -- "$rfp_pattern" "$rfp_scan_root/$rfp_source_file"
    if "$@"; then
      printf 'forbidden|%s|%s\n' "$rfp_rule_id" "$rfp_source_file" >>"$rfp_output_file"
    else
      rfp_status=$?
      if [ "$rfp_status" -ne 1 ]; then
        >&2 printf 'Forbidden-pattern scan %s failed for %s\n' \
          "$rfp_rule_id" "$rfp_source_file"
        return "$rfp_status"
      fi
    fi
  done <"$rfp_files_file"
}

record_forbidden_violations() {
  rfv_scan_root=$1
  rfv_files_file=$2
  rfv_output_file=$3

  record_forbidden_pattern \
    "$rfv_scan_root" "$rfv_files_file" "$rfv_output_file" \
    graph-under-core "" \
    'Sources/SwiftTUICore/(Resolve|Runtime)/' \
    0 0
  record_forbidden_pattern \
    "$rfv_scan_root" "$rfv_files_file" "$rfv_output_file" \
    moved-swifttui-runtime-path "" \
    'Sources/SwiftTUI/(Accessibility|Configuration|Diagnostics|Input|Lifecycle|RunLoop|Scenes|Support|Terminal|[^`[:space:]]+\.swift)' \
    0 0
  record_forbidden_pattern \
    "$rfv_scan_root" "$rfv_files_file" "$rfv_output_file" \
    separate-android-codable "" \
    'separate[^\n]*Codable[^\n]*(\n[[:space:]]*)?shape' \
    1 1
  record_forbidden_pattern \
    "$rfv_scan_root" "$rfv_files_file" "$rfv_output_file" \
    execution-mode-count docs/HOSTS-AND-PLATFORMS.md \
    'four execution modes' \
    0 1
  record_forbidden_pattern \
    "$rfv_scan_root" "$rfv_files_file" "$rfv_output_file" \
    accessibility-consumer-count docs/ACCESSIBILITY.md \
    '(four|five) accessibility consumers' \
    0 1
}

collect_violations() {
  cv_scan_root=$1
  cv_files_file=$2
  cv_output_file=$3
  cv_unsorted_file=$4

  record_cited_path_violations "$cv_scan_root" "$cv_files_file" "$cv_unsorted_file"
  record_forbidden_violations "$cv_scan_root" "$cv_files_file" "$cv_unsorted_file"
  LC_ALL=C sort -u "$cv_unsorted_file" >"$cv_output_file"
}

prepare_expected_ledger() {
  pel_ledger_file=$1
  pel_output_file=$2

  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$pel_ledger_file" |
    LC_ALL=C sort >"$pel_output_file"
}

compare_exact_ledger() {
  cel_ledger_file=$1
  cel_actual_file=$2
  cel_expected_file=$3

  prepare_expected_ledger "$cel_ledger_file" "$cel_expected_file"
  diff -u "$cel_expected_file" "$cel_actual_file"
}

run_self_test() {
  scratch_root=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-doc-path-self-test.XXXXXX")
  trap 'rm -rf "$scratch_root"' EXIT HUP INT TERM

  mkdir -p "$scratch_root/Sources" "$scratch_root/docs"
  : >"$scratch_root/Sources/Present.swift"
  cat >"$scratch_root/docs/clean.md" <<'EOF'
# Clean fixture

The implementation is at `Sources/Present.swift:12`.
EOF
  cat >"$scratch_root/docs/bad.md" <<'EOF'
# Bad fixture

This cites `Sources/Missing.swift` and the retired
`Sources/SwiftTUICore/Resolve/` ownership.
EOF

  clean_files="$scratch_root/clean-files"
  bad_files="$scratch_root/bad-files"
  clean_actual="$scratch_root/clean-actual"
  bad_actual="$scratch_root/bad-actual"
  scratch_unsorted="$scratch_root/unsorted"
  printf '%s\n' docs/clean.md >"$clean_files"
  printf '%s\n' docs/bad.md >"$bad_files"

  collect_violations "$scratch_root" "$clean_files" "$clean_actual" "$scratch_unsorted"
  if [ -s "$clean_actual" ]; then
    >&2 echo "doc cited-path self-test: clean fixture produced violations"
    >&2 cat "$clean_actual"
    exit 1
  fi

  collect_violations "$scratch_root" "$bad_files" "$bad_actual" "$scratch_unsorted"
  expected_bad="$scratch_root/expected-bad"
  cat >"$expected_bad" <<'EOF'
forbidden|graph-under-core|docs/bad.md
missing-path|docs/bad.md|Sources/Missing.swift
missing-path|docs/bad.md|Sources/SwiftTUICore/Resolve/
EOF
  if ! diff -u "$expected_bad" "$bad_actual"; then
    >&2 echo "doc cited-path self-test: bad fixture did not produce the expected violations"
    exit 1
  fi

  exact_ledger="$scratch_root/exact-ledger"
  duplicate_ledger="$scratch_root/duplicate-ledger"
  ledger_expected="$scratch_root/ledger-expected"
  cp "$expected_bad" "$exact_ledger"
  if ! compare_exact_ledger "$exact_ledger" "$bad_actual" "$ledger_expected" >/dev/null; then
    >&2 echo "doc cited-path self-test: exact fixture ledger did not match"
    exit 1
  fi
  cp "$expected_bad" "$duplicate_ledger"
  printf '%s\n' 'forbidden|graph-under-core|docs/bad.md' >>"$duplicate_ledger"
  if compare_exact_ledger "$duplicate_ledger" "$bad_actual" "$ledger_expected" >/dev/null; then
    >&2 echo "doc cited-path self-test: duplicate ledger row was normalized away"
    exit 1
  fi

  echo "[check_doc_cited_paths] self-test ok"
}

case "${1:-}" in
--self-test)
  run_self_test
  exit 0
  ;;
--print-current | "")
  ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  >&2 echo "Unknown argument: $1"
  usage >&2
  exit 2
  ;;
esac

scratch_root=$(mktemp -d "${TMPDIR:-/tmp}/swift-tui-doc-path-check.XXXXXX")
trap 'rm -rf "$scratch_root"' EXIT HUP INT TERM
files_file="$scratch_root/files"
actual_file="$scratch_root/actual"
unsorted_file="$scratch_root/unsorted"
expected_file="$scratch_root/expected"

collect_scan_files "$repo_root" "$files_file"
collect_violations "$repo_root" "$files_file" "$actual_file" "$unsorted_file"

if [ "${1:-}" = "--print-current" ]; then
  cat "$actual_file"
  exit 0
fi

if [ ! -f "$exceptions_file" ]; then
  >&2 echo "Missing exact exception ledger: $exceptions_file"
  exit 1
fi

if ! compare_exact_ledger "$exceptions_file" "$actual_file" "$expected_file"; then
  cat >&2 <<'EOF'
Stable documentation path/claim violations differ from the exact burn-down
ledger. Additions are regressions; stale rows must be deleted in the same
change that repairs their documentation.
EOF
  exit 1
fi

violation_count=$(wc -l <"$actual_file" | tr -d ' ')
echo "[check_doc_cited_paths] ok ($violation_count exact burn-down entries)"
