#!/usr/bin/env bash
#
# Toolchain-independent mutation checks for the public-API inventory generator.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${repo_root}/Scripts/data/public-api-fixtures"
generator="${repo_root}/Scripts/lib/generate_public_api_inventory.ts"
scratch="$(mktemp -d -t swift-tui-public-api-fixtures.XXXXXX)"
trap 'rm -rf "${scratch}"' EXIT

allow_missing_args=()
for module in \
  SwiftTUIRuntime \
  SwiftTUIProfiling \
  SwiftTUIViews \
  SwiftTUIAnimatedImage \
  SwiftTUIArguments \
  SwiftTUIPTYPrimitives \
  SwiftTUITerminal \
  SwiftTUITerminalWorkspace \
  SwiftTUICLI \
  SwiftTUIWASI \
  SwiftTUIWebHost \
  SwiftTUIWebHostCLI \
  SwiftTUIAndroidHost \
  SwiftTUICore \
  SwiftTUIPrimitives \
  SwiftTUIGraph \
  SwiftTUIPTYCPrimitives \
  SwiftTUITestSupport
do
  allow_missing_args+=(--allow-missing-module "${module}")
done

run_case() {
  local name="$1"
  local overrides="$2"
  local manifest="$3"
  local extra_graph="${4:-}"
  local case_dir="${scratch}/${name}"
  local graph_dir="${case_dir}/symbolgraph"
  local log="${case_dir}/output.log"

  mkdir -p "${graph_dir}"
  cp "${fixture_root}/symbolgraph/SwiftTUI.symbols.json" "${graph_dir}/"
  if [[ -n "${extra_graph}" ]]; then
    cp "${fixture_root}/${extra_graph}" "${graph_dir}/"
  fi

  if bun run "${generator}" \
    --symbolgraph-dir "${graph_dir}" \
    --overrides "${fixture_root}/${overrides}" \
    --package-manifest "${fixture_root}/${manifest}" \
    --baseline-md "${case_dir}/PUBLIC_API_BASELINE.md" \
    --baseline-flat "${case_dir}/public-api-baseline.txt" \
    --check \
    "${allow_missing_args[@]}" \
    >"${log}" 2>&1
  then
    echo "[check_public_api_generator_fixtures] ${name}: expected failure" >&2
    return 1
  fi
}

expect_failure() {
  local name="$1"
  local pattern="$2"
  local overrides="$3"
  local manifest="$4"
  local extra_graph="${5:-}"

  run_case "${name}" "${overrides}" "${manifest}" "${extra_graph}"
  if ! rg --fixed-strings --quiet -- "${pattern}" "${scratch}/${name}/output.log"; then
    echo "[check_public_api_generator_fixtures] ${name}: missing expected diagnostic:" >&2
    echo "  ${pattern}" >&2
    sed -n '1,120p' "${scratch}/${name}/output.log" >&2
    return 1
  fi
  echo "[check_public_api_generator_fixtures] ${name}: ok"
}

expect_failure \
  unknown-classification \
  "classifications.canonical key 'SwiftTUI.Unknown' does not match a top-level dump symbol" \
  unknown-classification.yml \
  Package.swift

expect_failure \
  unlisted-module \
  "symbol-graph module 'UnknownSupport' is neither configured nor explicitly unscanned" \
  overrides.yml \
  Package.swift \
  unknown-module/UnknownSupport.symbols.json

expect_failure \
  missing-product \
  "library product 'MissingProduct' is missing from ALL_MODULES" \
  overrides.yml \
  missing-product.Package.swift

expect_failure \
  removed-present \
  "symbol(s) are classified \"removed\" but still present" \
  removed-present.yml \
  Package.swift

# The exact bridge must suppress only the listed unresolved key. With all other
# configured modules explicitly allowed missing, this synthetic partial check
# should succeed.
bridge_dir="${scratch}/exact-migration-bridge"
mkdir -p "${bridge_dir}/symbolgraph"
cp "${fixture_root}/symbolgraph/SwiftTUI.symbols.json" "${bridge_dir}/symbolgraph/"
if ! bun run "${generator}" \
  --symbolgraph-dir "${bridge_dir}/symbolgraph" \
  --overrides "${fixture_root}/migration-bridge.yml" \
  --package-manifest "${fixture_root}/Package.swift" \
  --baseline-md "${bridge_dir}/PUBLIC_API_BASELINE.md" \
  --baseline-flat "${bridge_dir}/public-api-baseline.txt" \
  --check \
  "${allow_missing_args[@]}" \
  >"${bridge_dir}/output.log" 2>&1
then
  echo "[check_public_api_generator_fixtures] exact-migration-bridge: expected success" >&2
  sed -n '1,120p' "${bridge_dir}/output.log" >&2
  exit 1
fi
echo "[check_public_api_generator_fixtures] exact-migration-bridge: ok"

expect_failure \
  stale-migration-bridge \
  "migration_exceptions.classifications key 'SwiftTUI.Known' is stale or unused" \
  resolved-migration-bridge.yml \
  Package.swift

expect_failure \
  wildcard-migration-bridge \
  "migration_exceptions.classifications key 'SwiftTUI.*' is malformed" \
  wildcard-migration-bridge.yml \
  Package.swift

echo "[check_public_api_generator_fixtures] ok"
