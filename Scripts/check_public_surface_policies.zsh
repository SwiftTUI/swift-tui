#!/usr/bin/env zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0

fail() {
  print -u2 -- "$1"
  failures=1
}

contains_file() {
  local target="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ "$candidate" == "$target" ]]; then
      return 0
    fi
  done
  return 1
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

if ! rg -U -n -P --quiet -- '@preconcurrency @MainActor\s+public protocol View \{' \
  Sources/View/ViewFoundation.swift
then
  fail "The public View protocol must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '@ViewBuilder @MainActor @preconcurrency\s+var body: Body \{ get \}' \
  Sources/View/ViewFoundation.swift
then
  fail "View.body must stay @ViewBuilder @MainActor @preconcurrency."
fi

if ! rg -U -n -P --quiet -- '@preconcurrency @MainActor\s+public protocol Scene \{' \
  Sources/TerminalUI/App.swift
then
  fail "The public Scene protocol must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '@MainActor @preconcurrency\s+var body: Body \{ get \}' \
  Sources/TerminalUI/App.swift
then
  fail "Scene.body must stay @MainActor @preconcurrency."
fi

if ! rg -U -n -P --quiet -- '@preconcurrency @MainActor\s+public protocol App \{' \
  Sources/TerminalUI/App.swift
then
  fail "The public App protocol must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '@MainActor @preconcurrency\s+init\(\)' \
  Sources/TerminalUI/App.swift
then
  fail "App.init must stay @MainActor @preconcurrency."
fi

if ! rg -U -n -P --quiet -- '@SceneBuilder @MainActor @preconcurrency\s+var body: Body \{ get \}' \
  Sources/TerminalUI/App.swift
then
  fail "App.body must stay @SceneBuilder @MainActor @preconcurrency."
fi

if ! rg -U -n -P --quiet -- '@MainActor\s+public func resolve<' \
  Sources/View/ViewFoundation.swift
then
  fail "Resolver.resolve must stay @MainActor."
fi

if ! rg -U -n -P --quiet -- '@MainActor\s+public func render<' \
  Sources/TerminalUI/TerminalUI.swift
then
  fail "DefaultRenderer.render must stay @MainActor."
fi

if ! rg -U -n -P --quiet -- '@preconcurrency\s+public init\s*\(\s*@_inheritActorContext get: @escaping @isolated\(any\) @Sendable \(\) -> Value,\s*@_inheritActorContext set: @escaping @isolated\(any\) @Sendable \(Value\) -> Void' \
  Sources/View/ViewBaseTypes.swift
then
  fail "Binding.init(get:set:) must keep its actor-inheriting SwiftUI-style signature."
fi

if ! rg -n --fixed-strings --quiet -- '@_inheritActorContext' Sources/View/ViewModifiers.swift; then
  fail "ViewModifiers.task must keep actor-inheriting task closures."
fi

if ! rg -n --fixed-strings --quiet -- 'public func task<ID: Hashable & Sendable>(' \
  Sources/View/ViewModifiers.swift
then
  fail "The public task(id:) overload must stay available."
fi

if ! rg -n --fixed-strings --quiet -- 'action: @escaping @MainActor @Sendable () -> Void' \
  Sources/View/Button.swift
then
  fail "Button public actions must stay @MainActor @Sendable."
fi

if ! rg -n --fixed-strings --quiet -- 'private let handler: @MainActor @Sendable (LinkDestination) -> Bool' \
  Sources/View/Environment.swift
then
  fail "OpenLinkAction must stay main-actor-aware."
fi

actor_isolation_docs=(
  "README.md"
  "docs/RUNTIME.md"
  "docs/STATUS.md"
  "docs/PUBLIC_API_INVENTORY.md"
  "Sources/View/View.docc/Authoring-Views.md"
  "Sources/TerminalUI/TerminalUI.docc/Running-Apps.md"
)

for doc_file in "${actor_isolation_docs[@]}"; do
  if ! rg -n --fixed-strings --quiet -- '@MainActor' "$doc_file"; then
    fail "$doc_file should document the @MainActor authoring model."
  fi
done

anyview_policy_docs=(
  "AGENTS.md"
  "docs/PUBLIC_SURFACE_POLICY.md"
)

for doc_file in "${anyview_policy_docs[@]}"; do
  if ! rg -n --fixed-strings --quiet -- '## AnyView Policy' "$doc_file"; then
    fail "$doc_file should contain the AnyView policy heading."
  fi

  if ! rg -n --fixed-strings --quiet -- 'typed `@ViewBuilder` closures and generic `Content: View` storage' "$doc_file"; then
    fail "$doc_file should describe the typed @ViewBuilder and generic Content storage preference."
  fi

  if ! rg -n --fixed-strings --quiet -- 'scopedAnyView' "$doc_file"; then
    fail "$doc_file should mention scopedAnyView for deferred authored content."
  fi
done

if [[ ! -f Tests/ViewTests/ActorIsolationSurfaceTests.swift ]]; then
  fail "Tests/ViewTests/ActorIsolationSurfaceTests.swift should exist to pin the actor-isolated surface."
fi

public_surface_patterns=(
  '@ViewBuilder\s+[A-Za-z_]+\s*:\s*\(\)\s*->\s*\[AnyView\]'
  'public\s+(var|let)\s+[A-Za-z_]+\s*:\s*\[AnyView\]'
  'public\s+(var|let)\s+[A-Za-z_]+\s*:\s*\([^)]*\)\s*->\s*AnyView'
  'public\s+init\s*\([^)]*\[AnyView\]'
  'public\s+init\s*\([^)]*@ViewBuilder[^)]*->\s*AnyView'
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

stored_anyview_allowlist=(
  "Sources/TerminalUI/App.swift"
  "Sources/TerminalUICharts/BarChart.swift"
  "Sources/TerminalUICharts/BulletChart.swift"
  "Sources/TerminalUICharts/ColumnChart.swift"
  "Sources/TerminalUICharts/ComparisonChart.swift"
  "Sources/TerminalUICharts/HeatStrip.swift"
  "Sources/TerminalUICharts/Legend.swift"
  "Sources/TerminalUICharts/Meter.swift"
  "Sources/TerminalUICharts/Sparkline.swift"
  "Sources/TerminalUICharts/StackedBarChart.swift"
  "Sources/TerminalUICharts/ThresholdGauge.swift"
  "Sources/View/AdjustableValueControls.swift"
  "Sources/View/Button.swift"
  "Sources/View/Collections.swift"
  "Sources/View/ContainerViews.swift"
  "Sources/View/Environment.swift"
  "Sources/View/LabeledContainers.swift"
  "Sources/View/Layout.swift"
  "Sources/View/Menu.swift"
  "Sources/View/NavigationViews.swift"
  "Sources/View/OutlineViews.swift"
  "Sources/View/Picker.swift"
  "Sources/View/PickerRendering.swift"
  "Sources/View/PresentationModifiers.swift"
  "Sources/View/ProgressView.swift"
  "Sources/View/SecureField.swift"
  "Sources/View/ValueControls.swift"
  "Sources/View/ViewCompositionHelpers.swift"
  "Sources/View/ViewFoundation.swift"
  "Tests/TerminalUITests/NonAggregatingViewFixtureTests.swift"
)

stored_anyview_matches="$(
  rg -n -P \
    --glob '*.swift' \
    --glob '!Sources/Vendor/**' \
    -- '^\s*(public|internal|package|private|fileprivate)?\s*(var|let)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*(\[\s*AnyView\s*\]|AnyView\??|\([^)]*\)\s*->\s*AnyView)\s*(=\s*.+)?$' \
    Sources Tests || true
)"

if [[ -n "$stored_anyview_matches" ]]; then
  match_files=("${(@f)stored_anyview_matches}")
  match_line=""
  file=""
  for match_line in "${match_files[@]}"; do
    file="${match_line%%:*}"
    if contains_file "$file" "${stored_anyview_allowlist[@]}"; then
      continue
    fi

    if rg -n --fixed-strings --quiet -- 'AnyView policy:' "$file"; then
      continue
    fi

    fail "$file introduces stored AnyView erasure without an allowlist entry or nearby 'AnyView policy:' comment."
  done
fi

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
