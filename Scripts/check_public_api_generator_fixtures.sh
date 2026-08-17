#!/usr/bin/env bash
#
# Toolchain-independent mutation checks for the public-API inventory generator.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${repo_root}/Scripts/data/public-api-fixtures"
generator="${repo_root}/Scripts/lib/generate_public_api_inventory.ts"
materializer="${repo_root}/Scripts/lib/materialize_override_entries.ts"
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
  SwiftTUITerminalEmulation \
  SwiftTUITerminal \
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

materializer_dir="${scratch}/materializer"
mkdir -p "${materializer_dir}"
if ! bun run "${materializer}" \
  --baseline "${fixture_root}/PUBLIC_API_BASELINE.md" \
  --overrides "${fixture_root}/overrides.yml" \
  --module SwiftTUI \
  >"${materializer_dir}/missing.yml" \
  2>"${materializer_dir}/missing.log"
then
  echo "[check_public_api_generator_fixtures] materializer-output: expected success" >&2
  sed -n '1,120p' "${materializer_dir}/missing.log" >&2
  exit 1
fi
if ! rg --fixed-strings --quiet \
  -- "- SwiftTUI.NewSurface" \
  "${materializer_dir}/missing.yml"
then
  echo "[check_public_api_generator_fixtures] materializer-output: missing entry" >&2
  sed -n '1,120p' "${materializer_dir}/missing.yml" >&2
  exit 1
fi
echo "[check_public_api_generator_fixtures] materializer-output: ok"

if bun run "${materializer}" \
  --baseline "${fixture_root}/malformed-PUBLIC_API_BASELINE.md" \
  --overrides "${fixture_root}/materialized-overrides.yml" \
  --module SwiftTUI \
  --check \
  >"${materializer_dir}/malformed-baseline.log" \
  2>&1
then
  echo "[check_public_api_generator_fixtures] materializer-malformed-baseline: expected failure" >&2
  exit 1
fi
if ! rg --fixed-strings --quiet \
  -- "Baseline entry-count mismatch for 'SwiftTUI': summary declares 2, parsed 0" \
  "${materializer_dir}/malformed-baseline.log"
then
  echo "[check_public_api_generator_fixtures] materializer-malformed-baseline: missing diagnostic" >&2
  sed -n '1,120p' "${materializer_dir}/malformed-baseline.log" >&2
  exit 1
fi
echo "[check_public_api_generator_fixtures] materializer-malformed-baseline: ok"

if bun run "${materializer}" \
  --baseline "${fixture_root}/PUBLIC_API_BASELINE.md" \
  --overrides "${fixture_root}/overrides.yml" \
  --module SwiftTUI \
  --check \
  >"${materializer_dir}/check-failure.log" \
  2>&1
then
  echo "[check_public_api_generator_fixtures] materializer-check-failure: expected failure" >&2
  exit 1
fi
if ! rg --fixed-strings --quiet \
  -- "canonical: SwiftTUI.NewSurface" \
  "${materializer_dir}/check-failure.log"
then
  echo "[check_public_api_generator_fixtures] materializer-check-failure: missing diagnostic" >&2
  sed -n '1,120p' "${materializer_dir}/check-failure.log" >&2
  exit 1
fi
echo "[check_public_api_generator_fixtures] materializer-check-failure: ok"

if ! bun run "${materializer}" \
  --baseline "${fixture_root}/PUBLIC_API_BASELINE.md" \
  --overrides "${fixture_root}/materialized-overrides.yml" \
  --module SwiftTUI \
  --check \
  >"${materializer_dir}/check-success.log" \
  2>&1
then
  echo "[check_public_api_generator_fixtures] materializer-check-success: expected success" >&2
  sed -n '1,120p' "${materializer_dir}/check-success.log" >&2
  exit 1
fi
echo "[check_public_api_generator_fixtures] materializer-check-success: ok"

echo "[check_public_api_generator_fixtures] ok"
