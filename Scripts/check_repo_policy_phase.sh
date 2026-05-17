#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

. "$repo_root/Scripts/lib/repo_policy_checks.sh"

run_repo_policy_phase "$repo_root" direct

echo "[check_repo_policy_phase] ok"
