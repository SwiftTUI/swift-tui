#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

ledger=docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
followup_audit=docs/proposals/PIPELINE_DRIVER_FOLLOWUP_AUDIT.md
original_audit=docs/proposals/PIPELINE_DRIVER_AUDIT.md
policy_phase=Scripts/lib/repo_policy_checks.sh

failures=0

fail() {
  failures=$((failures + 1))
  >&2 echo "error: $1"
}

require_file() {
  if [ ! -f "$1" ]; then
    fail "missing required file: $1"
  fi
}

require_file "$ledger"
require_file "$followup_audit"
require_file "$original_audit"
require_file "$policy_phase"

current_table=$(mktemp)
current_status=$(mktemp)
trap 'rm -f "$current_table" "$current_status"' EXIT

awk '
  /^\| Finding \| Mechanism \| DoD command \| Verified-by commit \|/ {
    in_table = 1
  }
  in_table && /^## / {
    exit
  }
  in_table {
    print
  }
' "$ledger" >"$current_table"

if [ ! -s "$current_table" ]; then
  fail "ledger is missing the canonical current resolution table"
fi

for finding in F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 F13 F14; do
  row=$(grep -E "^\\| ${finding}[[:space:]]*\\|" "$current_table" || true)
  if [ -z "$row" ]; then
    fail "ledger current table is missing ${finding}"
    continue
  fi
  if printf '%s\n' "$row" | rg -q "_pending_"; then
    fail "ledger current table still has pending fields for ${finding}"
  fi
  if ! printf '%s\n' "$row" | rg -q "^\\| ${finding}[[:space:]]*\\|[[:space:]]*(code|code\\+test|test)[[:space:]]*\\|"; then
    fail "ledger current table has invalid mechanism for ${finding}: $row"
  fi
  if ! printf '%s\n' "$row" | rg -q "\\|[[:space:]]*[0-9a-f]{7,}([, ][, 0-9a-f]*)?[[:space:]]*\\|$"; then
    fail "ledger current table has no git short hash for ${finding}: $row"
  fi
done

if rg -n "\\|[[:space:]]*docs[[:space:]]*\\|" "$current_table"; then
  fail "ledger current table contains a docs-only mechanism"
fi

if ! rg -q "^## Independent audit entrypoints" "$ledger"; then
  fail "ledger does not explain the independent audit entrypoints"
fi

awk '
  /^## Current independent re-audit status/ {
    in_status = 1
    next
  }
  in_status && /^## / {
    exit
  }
  in_status {
    print
  }
' "$ledger" >"$current_status"

if [ ! -s "$current_status" ]; then
  fail "ledger is missing the current independent re-audit status section"
fi

if rg -n "STILL-OBSERVABLE" "$current_status"; then
  fail "current independent re-audit status still reports observable findings"
fi

for finding in F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 F13 F14; do
  if ! rg -q "^\\| ${finding}[[:space:]]*\\| RESOLVED \\|" "$current_status"; then
    fail "current independent re-audit status is missing RESOLVED row for ${finding}"
  fi
done

if ! rg -q "^\\| # \\| Finding \\| Severity \\| Class \\| Resolution mechanism \\|" \
  "$followup_audit"; then
  fail "follow-up audit summary is missing the resolution mechanism column"
fi

if ! rg -q "^\\| # \\| Finding \\| Outcome \\| Resolution mechanism \\|" \
  "$original_audit"; then
  fail "original audit summary is missing the historical resolution mechanism column"
fi

if ! rg -q "PIPELINE_DRIVER_RESOLUTION_LEDGER.md" "$followup_audit"; then
  fail "follow-up audit does not link to the resolution ledger"
fi

if ! rg -q "check_pipeline_driver_resolution_ledger.sh" "$followup_audit"; then
  fail "follow-up audit does not name the mechanical ledger checker"
fi

if ! rg -q "check_pipeline_driver_resolution_ledger.sh" "$policy_phase"; then
  fail "repo policy phase does not run the pipeline driver ledger checker"
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

echo "[check_pipeline_driver_resolution_ledger] ok"
