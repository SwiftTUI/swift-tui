#!/usr/bin/env zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0

fail() {
  print -u2 -- "$1"
  failures=1
}

public_behavior_suite_files=(
  "Tests/TerminalUITests/AppRuntimeTests.swift"
  "Tests/TerminalUITests/CollectionSupportTests.swift"
  "Tests/TerminalUITests/Phase0FoundationTests.swift"
  "Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift"
  "Tests/TerminalUITests/Phase5ReliabilityGatesTests.swift"
  "Tests/TerminalUITests/Support/InteractiveDemoTestSupport.swift"
  "Tests/TerminalUITests/ViewCompositionSurfaceTests.swift"
)

banned_construction_tokens=(
  "AnyViewNode("
  "Resolver("
  "ViewNode"
  "AnyView(erasing:"
  "SemanticMetadataView"
  "IdentityView"
  "LayoutMetadataView"
  "DrawMetadataView"
  "Theme"
  ".theme"
  "LocalActionRegistry"
  "LocalKeyHandlerRegistry"
  "LocalLifecycleRegistry"
  "LocalTaskRegistry"
  "TaskRegistration"
  "LifecycleHandlerSnapshot"
  "LocalKeyEvent"
  "previousLifecycleState:"
)

for suite_file in "${public_behavior_suite_files[@]}"; do
  if [[ ! -f "$suite_file" ]]; then
    fail "$suite_file is missing from the public-behavior suite allowlist."
    continue
  fi

  for token in "${banned_construction_tokens[@]}"; do
    if rg -n --fixed-strings --quiet -- "$token" "$suite_file"; then
      fail "$suite_file unexpectedly contains the migration-era construction token $token."
    fi
  done
done

view_protocol_block="$(awk '
  /public protocol View \{/ { collecting = 1 }
  /extension Never: View \{/ { collecting = 0 }
  collecting { print }
' Sources/View/ViewFoundation.swift)"

if [[ -z "$view_protocol_block" ]]; then
  fail "Could not isolate the public View protocol block in Sources/View/ViewFoundation.swift."
else
  [[ "$view_protocol_block" == *"associatedtype Body: View = Never"* ]] \
    || fail "The public View protocol must keep associatedtype Body: View = Never."
  [[ "$view_protocol_block" == *"var body: Body { get }"* ]] \
    || fail "The public View protocol must stay body-only."
  [[ "$view_protocol_block" != *"ViewNode"* ]] \
    || fail "The public View protocol block must not expose ViewNode."
  [[ "$view_protocol_block" != *"resolveElements"* ]] \
    || fail "The public View protocol block must not expose resolveElements."
fi

public_surface_patterns=(
  '@ViewBuilder\s+[A-Za-z_]+\s*:\s*\(\)\s*->\s*\[AnyView\]'
  'public\s+(var|let)\s+[A-Za-z_]+\s*:\s*\[AnyView\]'
  'public\s+init\s*\([^)]*\[AnyView\]'
  'public\s+init\s*\(\s*erasing:'
  'public\s+init\s*\([^)]*localActionRegistry:'
  'public\s+init\s*\([^)]*localKeyHandlerRegistry:'
  'public\s+init\s*\([^)]*localLifecycleRegistry:'
  'public\s+init\s*\([^)]*localTaskRegistry:'
  'public\s+func\s+render\s*\([^)]*previousLifecycleState:'
)

for pattern in "${public_surface_patterns[@]}"; do
  if rg -n -P \
    --glob '*.swift' \
    --glob '!Sources/Vendor/**' \
    -- "$pattern" Sources
  then
    fail "Unexpected public AnyView-array or node-erasure surface matched $pattern."
  fi
done

non_public_seam_declarations=(
  'public enum Package'
  'public final class TaskRegistration'
  'public final class LocalActionRegistry'
  'public enum LocalKeyEvent'
  'public final class LocalKeyHandlerRegistry'
  'public struct LifecycleHandlerSnapshot'
  'public final class LocalLifecycleRegistry'
  'public final class LocalTaskRegistry'
  'public struct IDView'
  'public struct LayoutMetadataModifier'
  'public struct DrawMetadataModifier'
  'public struct SemanticMetadataModifier'
  'public struct EnvironmentWritingModifier'
  'public struct EnvironmentTransformModifier'
  'public struct PaddingView'
  'public struct FrameView'
  'public struct OverlayView'
  'public struct BackgroundView'
)

for declaration in "${non_public_seam_declarations[@]}"; do
  if rg -n --fixed-strings --quiet -- "$declaration" Sources; then
    fail "Unexpected public API seam declaration found: $declaration."
  fi
done

removed_runtime_factory_symbols=(
  'makeViewResolver'
  'makeNoOpRenderer'
)

for symbol in "${removed_runtime_factory_symbols[@]}"; do
  if rg -n --glob '*.swift' --fixed-strings --quiet -- "$symbol" Sources; then
    fail "Unexpected runtime compatibility factory remains in source: $symbol."
  fi
done

retired_legacy_identifier_tokens=(
  'foregroundStyle: String'
  'backgroundStyle: String'
  'borderStyle: String'
  'emphasis: [String]'
  'styleRawValue'
  'RouteID.rawValue'
  'ExpressibleByStringLiteral'
  'ActionDispatcher'
  'keyboardActionRole'
  'pointerHitPolicy'
  'actionRoutes'
  'actionRole:'
  'focusable(role:'
)

for token in "${retired_legacy_identifier_tokens[@]}"; do
  if rg -n --glob '*.swift' --fixed-strings --quiet -- "$token" Sources; then
    fail "Retired legacy identifier surface reappeared in source: $token."
  fi
done

if ! rg -n --fixed-strings --quiet -- 'Removed From The Public Surface' docs/PUBLIC_API_INVENTORY.md; then
  fail "docs/PUBLIC_API_INVENTORY.md should keep the 'Removed From The Public Surface' section."
fi

if ! rg -n --fixed-strings --quiet -- 'Package-Only Transitional Seams' docs/PUBLIC_API_INVENTORY.md; then
  fail "docs/PUBLIC_API_INVENTORY.md should keep the 'Package-Only Transitional Seams' section."
fi

if rg -n --fixed-strings --quiet -- 'These symbols remain public today' docs/PUBLIC_API_INVENTORY.md; then
  fail "docs/PUBLIC_API_INVENTORY.md still contains outdated migration-era wording."
fi


runtime_docs=(
  "README.md"
  "docs/ARCHITECTURE.md"
  "docs/PUBLIC_API_INVENTORY.md"
  "docs/PUBLIC_SURFACE_POLICY.md"
  "docs/SOURCE_LAYOUT.md"
)

for doc_file in "${runtime_docs[@]}"; do
  if rg -n -P --quiet -- '(?<!`)``(?!`)' "$doc_file"; then
    fail "$doc_file still contains an empty inline-code runtime placeholder."
  fi
done

if ! rg -n --fixed-strings --quiet -- '`TerminalUI`' README.md; then
  fail "README.md should name TerminalUI explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '`TerminalUIScenes`' README.md; then
  fail "README.md should name TerminalUIScenes explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '### `TerminalUI`' docs/PUBLIC_API_INVENTORY.md; then
  fail "docs/PUBLIC_API_INVENTORY.md should classify the TerminalUI runtime explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '### `TerminalUIScenes`' docs/PUBLIC_API_INVENTORY.md; then
  fail "docs/PUBLIC_API_INVENTORY.md should classify the TerminalUIScenes runtime explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '`TerminalUI`, with `TerminalUIScenes` as the optional multi-scene layer' docs/PUBLIC_SURFACE_POLICY.md; then
  fail "docs/PUBLIC_SURFACE_POLICY.md should name TerminalUI and TerminalUIScenes explicitly."
fi

if ! rg -n --fixed-strings --quiet -- 'Experimental or showcase targets follow the same rule' docs/PUBLIC_SURFACE_POLICY.md; then
  fail "docs/PUBLIC_SURFACE_POLICY.md should keep the showcase-target policy heading."
fi

if ! rg -n --fixed-strings --quiet -- 'they should not be exported as package products' docs/PUBLIC_SURFACE_POLICY.md; then
  fail "docs/PUBLIC_SURFACE_POLICY.md should keep the showcase export policy."
fi

if (( failures != 0 )); then
  exit 1
fi
