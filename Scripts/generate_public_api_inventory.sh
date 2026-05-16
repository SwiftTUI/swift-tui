#!/usr/bin/env bash
#
# Generates `docs/PUBLIC_API_BASELINE.md` (curated grouping) and
# `docs/.public-api-baseline.txt` (flat sorted list) from
# `swift package dump-symbol-graph`.
#
# Together those two files are the committed, diff-checkable enumeration
# of the package's public Swift surface. PRs that add or remove a public
# symbol see the change show up here.
#
# Classification (canonical / package-only seam / removed / etc.) is
# applied from `docs/public_api_overrides.yml`. Symbols not in that file
# are reported as `pending-review`.
#
# Usage:
#   Scripts/generate_public_api_inventory.sh            # regenerate baseline
#   Scripts/generate_public_api_inventory.sh --check    # fail if the committed
#                                                       # baseline is stale or
#                                                       # if there are unclassified
#                                                       # symbols
#
# Requires `swiftly` and `bun` on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

CHECK_ONLY=0
for arg in "$@"; do
  case "${arg}" in
    --check)
      CHECK_ONLY=1
      ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      echo "Usage: $0 [--check]" >&2
      exit 2
      ;;
  esac
done

# Symbol graph output lives under the selected scratch directory. Keep this
# isolated from the repo's normal `.build` tree so stale test products cannot
# leak into CI policy checks.
echo "[generate_public_api_inventory] Running swift package dump-symbol-graph..." >&2
SYMBOLGRAPH_SCRATCH_DIR=".build/public-api-symbolgraph"
DUMP_LOG="$(mktemp -t swift-tui-symbolgraph.XXXXXX)"
trap 'rm -f "${DUMP_LOG}"' EXIT
rm -rf "${SYMBOLGRAPH_SCRATCH_DIR}"
if ! swiftly run swift package \
  --scratch-path "${SYMBOLGRAPH_SCRATCH_DIR}" \
  dump-symbol-graph \
  --minimum-access-level public \
  >"${DUMP_LOG}" 2>&1; then
  if grep -Eq "Failed to emit symbol graph for '.*Package(Discovered)?Tests'" "${DUMP_LOG}"; then
    echo "[generate_public_api_inventory] Ignoring SwiftPM synthetic package-test symbol graph failure." >&2
    grep -E "Failed to emit symbol graph" "${DUMP_LOG}" >&2 || true
  else
    cat "${DUMP_LOG}" >&2
    exit 1
  fi
fi

# Locate the symbolgraph directory the SwiftPM driver chose (per-arch).
SYMBOLGRAPH_DIR="$(
  find "${SYMBOLGRAPH_SCRATCH_DIR}" -type d -name symbolgraph -prune -print 2>/dev/null \
    | head -n 1
)"
if [[ -z "${SYMBOLGRAPH_DIR:-}" ]] || [[ ! -d "${SYMBOLGRAPH_DIR}" ]]; then
  echo "[generate_public_api_inventory] Could not locate symbolgraph output directory under ${SYMBOLGRAPH_SCRATCH_DIR}/" >&2
  exit 1
fi

echo "[generate_public_api_inventory] Symbolgraph dir: ${SYMBOLGRAPH_DIR}" >&2

# Drive the markdown + flat-list generator.
GENERATE_ARGS=(
  --symbolgraph-dir "${SYMBOLGRAPH_DIR}"
  --overrides "docs/public_api_overrides.yml"
  --baseline-md "docs/PUBLIC_API_BASELINE.md"
  --baseline-flat "docs/.public-api-baseline.txt"
)
if [[ "$(uname -s)" == "Linux" ]]; then
  GENERATE_ARGS+=(--allow-missing-module SwiftUIHost)
fi
if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  GENERATE_ARGS+=(--check)
fi

bun run "${SCRIPT_DIR}/lib/generate_public_api_inventory.ts" "${GENERATE_ARGS[@]}"
