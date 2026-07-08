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
# `--check` also runs a report-only doc-comment ratchet: it counts the
# `canonical` symbols with no `///` summary. See ENFORCE_DOC_COMMENTS in
# Scripts/lib/generate_public_api_inventory.ts.
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

SWIFT_PACKAGE_ARGS=(
  --scratch-path "${SYMBOLGRAPH_SCRATCH_DIR}"
)
PUBLIC_API_SWIFT_JOBS="${STUI_PUBLIC_API_SWIFT_JOBS:-}"
if [[ -z "${PUBLIC_API_SWIFT_JOBS}" && "$(uname -s)" == "Linux" ]]; then
  PUBLIC_API_SWIFT_JOBS=4
fi
if [[ -n "${PUBLIC_API_SWIFT_JOBS}" ]]; then
  SWIFT_PACKAGE_ARGS+=(--jobs "${PUBLIC_API_SWIFT_JOBS}")
fi

run_symbol_graph_dump() {
  if ! swiftly run swift package \
    "${SWIFT_PACKAGE_ARGS[@]}" \
    dump-symbol-graph \
    --minimum-access-level public \
    "$@" \
    >"${DUMP_LOG}" 2>&1; then
    if grep -Eq "Failed to emit symbol graph for '.*Package(Discovered)?Tests'" "${DUMP_LOG}"; then
      echo "[generate_public_api_inventory] Ignoring SwiftPM synthetic package-test symbol graph failure." >&2
      grep -E "Failed to emit symbol graph" "${DUMP_LOG}" >&2 || true
    else
      cat "${DUMP_LOG}" >&2
      exit 1
    fi
  fi
}

# Locate the symbolgraph directory the SwiftPM driver chose (per-arch).
locate_symbolgraph_dir() {
  find "${SYMBOLGRAPH_SCRATCH_DIR}" -type d -name symbolgraph -prune -print 2>/dev/null \
    | head -n 1
}

run_symbol_graph_dump

SYMBOLGRAPH_DIR="$(locate_symbolgraph_dir)"
if [[ -z "${SYMBOLGRAPH_DIR:-}" ]] || [[ ! -d "${SYMBOLGRAPH_DIR}" ]]; then
  echo "[generate_public_api_inventory] Could not locate symbolgraph output directory under ${SYMBOLGRAPH_SCRATCH_DIR}/" >&2
  exit 1
fi

echo "[generate_public_api_inventory] Symbolgraph dir: ${SYMBOLGRAPH_DIR}" >&2

# Preserve the public dump, then rerun with SPI included (warm build — only
# the extraction reruns). The SPI-only delta between the two dumps becomes
# docs/.spi-api-baseline.txt, the tracked @_spi host contract (F58).
PUBLIC_SYMBOLGRAPH_KEEP="$(mktemp -d -t swift-tui-symbolgraph-public.XXXXXX)"
trap 'rm -f "${DUMP_LOG}"; rm -rf "${PUBLIC_SYMBOLGRAPH_KEEP}"' EXIT
cp -R "${SYMBOLGRAPH_DIR}/." "${PUBLIC_SYMBOLGRAPH_KEEP}/"

echo "[generate_public_api_inventory] Running SPI-inclusive dump-symbol-graph..." >&2
rm -rf "${SYMBOLGRAPH_DIR}"
run_symbol_graph_dump --include-spi-symbols

SPI_SYMBOLGRAPH_DIR="$(locate_symbolgraph_dir)"
if [[ -z "${SPI_SYMBOLGRAPH_DIR:-}" ]] || [[ ! -d "${SPI_SYMBOLGRAPH_DIR}" ]]; then
  echo "[generate_public_api_inventory] Could not locate SPI symbolgraph output directory under ${SYMBOLGRAPH_SCRATCH_DIR}/" >&2
  exit 1
fi

# Drive the markdown + flat-list generator.
GENERATE_ARGS=(
  --symbolgraph-dir "${PUBLIC_SYMBOLGRAPH_KEEP}"
  --overrides "docs/public_api_overrides.yml"
  --baseline-md "docs/PUBLIC_API_BASELINE.md"
  --baseline-flat "docs/.public-api-baseline.txt"
  --spi-symbolgraph-dir "${SPI_SYMBOLGRAPH_DIR}"
  --baseline-spi "docs/.spi-api-baseline.txt"
)
if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  GENERATE_ARGS+=(--check)
fi

bun run "${SCRIPT_DIR}/lib/generate_public_api_inventory.ts" "${GENERATE_ARGS[@]}"
