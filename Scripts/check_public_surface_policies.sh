#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

failures=0

fail() {
  >&2 echo "$1"
  failures=1
}

view_protocol_block=$(awk '
  /public protocol View \{/ { collecting = 1 }
  /extension Never: View \{/ { collecting = 0 }
  collecting { print }
' Sources/View/Foundation/ViewFoundation.swift)

if [ -z "$view_protocol_block" ]; then
  fail "Could not isolate the public View protocol block in Sources/View/Foundation/ViewFoundation.swift."
else
  case "$view_protocol_block" in
  *"associatedtype Body: View = Never"*) ;;
  *) fail "The public View protocol must keep associatedtype Body: View = Never." ;;
  esac
  case "$view_protocol_block" in
  *"var body: Body { get }"*) ;;
  *) fail "The public View protocol must stay body-only." ;;
  esac
  case "$view_protocol_block" in
  *"ViewNode"*) fail "The public View protocol block must not expose ViewNode." ;;
  esac
  case "$view_protocol_block" in
  *"resolveElements"*) fail "The public View protocol block must not expose resolveElements." ;;
  esac
fi

if ! rg -U -n -P --quiet -- '(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+public protocol View \{' \
  Sources/View/Foundation/ViewFoundation.swift; then
  fail "The public View protocol must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '@ViewBuilder\s+(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+var body: Body \{ get \}' \
  Sources/View/Foundation/ViewFoundation.swift; then
  fail "View.body must stay @ViewBuilder and @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+public protocol Scene \{' \
  Sources/SwiftTUI/App.swift; then
  fail "The public Scene protocol must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+var body: Body \{ get \}' \
  Sources/SwiftTUI/App.swift; then
  fail "Scene.body must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+public protocol App \{' \
  Sources/SwiftTUI/App.swift; then
  fail "The public App protocol must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+init\(\)' \
  Sources/SwiftTUI/App.swift; then
  fail "App.init must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '@SceneBuilder\s+(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+var body: Body \{ get \}' \
  Sources/SwiftTUI/App.swift; then
  fail "App.body must stay @SceneBuilder and @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '@MainActor\s+public func resolve<' \
  Sources/View/Foundation/ViewFoundation.swift; then
  fail "Resolver.resolve must stay @MainActor."
fi

if ! rg -U -n -P --quiet -- '@MainActor\s+public func render<' \
  Sources/SwiftTUI/SwiftTUI.swift; then
  fail "DefaultRenderer.render must stay @MainActor."
fi

if ! rg -U -n -P --quiet -- '(?:@preconcurrency\s+)?public init\s*\(\s*@_inheritActorContext get: @escaping @isolated\(any\) @Sendable \(\) -> Value,\s*@_inheritActorContext set: @escaping @isolated\(any\) @Sendable \(Value\) -> Void' \
  Sources/View/Foundation/ViewBaseTypes.swift; then
  fail "Binding.init(get:set:) must keep its actor-inheriting SwiftUI-style signature."
fi

if ! rg -n --fixed-strings --quiet -- '@_inheritActorContext' Sources/View/Modifiers/ViewModifiers.swift; then
  fail "ViewModifiers.task must keep actor-inheriting task closures."
fi

if ! rg -n --fixed-strings --quiet -- 'public func task<ID: Equatable>(' \
  Sources/View/Modifiers/ViewModifiers.swift; then
  fail "The public task(id:) overload must stay available."
fi

if ! rg -n --fixed-strings --quiet -- 'action: @escaping @MainActor @Sendable () -> Void' \
  Sources/View/Controls/Button.swift; then
  fail "Button public actions must stay @MainActor @Sendable."
fi

if ! rg -n --fixed-strings --quiet -- 'private let handler: @MainActor @Sendable (LinkDestination) -> Bool' \
  Sources/View/Environment/Environment.swift; then
  fail "OpenLinkAction must stay main-actor-aware."
fi

while IFS= read -r doc_file; do
  [ -z "$doc_file" ] && continue
  if ! rg -n --fixed-strings --quiet -- '@MainActor' "$doc_file"; then
    fail "$doc_file should document the @MainActor authoring model."
  fi
done <<'EOF'
docs/RUNTIME.md
docs/STATUS.md
docs/PUBLIC_API_INVENTORY.md
Sources/View/View.docc/Authoring-Views.md
Sources/SwiftTUI/SwiftTUI.docc/Running-Apps.md
EOF

while IFS= read -r doc_file; do
  [ -z "$doc_file" ] && continue
  if ! rg -n --fixed-strings --quiet -- '## AnyView Policy' "$doc_file"; then
    fail "$doc_file should contain the AnyView policy heading."
  fi

  if ! rg -n --fixed-strings --quiet -- '@ViewBuilder' "$doc_file"; then
    fail "$doc_file should mention @ViewBuilder in the AnyView policy."
  fi

  if ! rg -n --fixed-strings --quiet -- 'Content: View' "$doc_file"; then
    fail "$doc_file should mention generic Content: View storage in the AnyView policy."
  fi

  if ! rg -n --fixed-strings --quiet -- 'scopedAnyView' "$doc_file"; then
    fail "$doc_file should mention scopedAnyView for deferred authored content."
  fi
done <<'EOF'
AGENTS.md
docs/PUBLIC_SURFACE_POLICY.md
EOF

if [ ! -f Tests/ViewTests/ActorIsolationSurfaceTests.swift ] && [ ! -f Tests/SwiftTUITests/ActorIsolationSurfaceTests.swift ]; then
  fail "Tests/ViewTests/ActorIsolationSurfaceTests.swift should exist to pin the actor-isolated surface."
fi

while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue
  if rg -n -P \
    --glob '*.swift' \
    --glob '!Sources/Vendor/**' \
    -- "$pattern" Sources; then
    fail "Unexpected public AnyView-array or node-erasure surface matched $pattern."
  fi
done <<'EOF'
public\s+typealias\s+[A-Za-z_][A-Za-z0-9_]*(?:<[^>\n]+>)?\s*=\s*(?:\n\s*)?\([^)]*\)\s*->\s*AnyView
@ViewBuilder\s+[A-Za-z_]+\s*:\s*\(\)\s*->\s*\[AnyView\]
public\s+(var|let)\s+[A-Za-z_]+\s*:\s*\[AnyView\]
public\s+(var|let)\s+[A-Za-z_]+\s*:\s*\([^)]*\)\s*->\s*AnyView
public\s+init\s*\([^)]*\[AnyView\]
public\s+init\s*\([^)]*@ViewBuilder[^)]*->\s*AnyView
public\s+init\s*\(\s*erasing:
public\s+init\s*\([^)]*localActionRegistry:
public\s+init\s*\([^)]*localKeyHandlerRegistry:
public\s+init\s*\([^)]*localLifecycleRegistry:
public\s+init\s*\([^)]*localTaskRegistry:
public\s+func\s+render\s*\([^)]*previousLifecycleState:
EOF

stored_anyview_matches=$(
  rg -n -P \
    --glob '*.swift' \
    --glob '!Sources/Vendor/**' \
    -- '^\s*(public|internal|package|private|fileprivate)?\s*(var|let)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*(\[\s*AnyView\s*\]|AnyView\??|\([^)]*\)\s*->\s*AnyView)\s*(=\s*.+)?$' \
    Sources || true
)

if [ -n "$stored_anyview_matches" ]; then
  matched_files=$(
    printf '%s\n' "$stored_anyview_matches" |
      cut -d: -f1 |
      LC_ALL=C sort -u
  )
  OLD_IFS=$IFS
  IFS='
'
  for file in $matched_files; do
    if ! rg -n --fixed-strings --quiet -- 'AnyView policy:' "$file"; then
      fail "$file retains stored AnyView erasure but lacks an 'AnyView policy:' comment."
    fi
  done
  IFS=$OLD_IFS
fi

while IFS= read -r declaration; do
  [ -z "$declaration" ] && continue
  if rg -n --fixed-strings --quiet -- "$declaration" Sources; then
    fail "Unexpected public API seam declaration found: $declaration."
  fi
done <<'EOF'
public enum Package
public final class TaskRegistration
public final class LocalActionRegistry
public enum LocalKeyEvent
public final class LocalKeyHandlerRegistry
public struct LifecycleHandlerSnapshot
public final class LocalLifecycleRegistry
public final class LocalTaskRegistry
public struct IDView
public struct PaddingView
public struct FrameView
public struct OverlayView
public struct BackgroundView
public struct TagValueView
EOF

while IFS= read -r symbol; do
  [ -z "$symbol" ] && continue
  if rg -n --glob '*.swift' --fixed-strings --quiet -- "$symbol" Sources; then
    fail "Retired modifier-wrapper seam reappeared in source: $symbol."
  fi
done <<'EOF'
resolveWrapperContent
withTabChildInnerContent
TabChildMetadataContributing
TransitionEffectContributing
transitionChildForProbe
EOF

while IFS= read -r symbol; do
  [ -z "$symbol" ] && continue
  if rg -n --glob '*.swift' --fixed-strings --quiet -- "$symbol" Sources; then
    fail "Unexpected runtime compatibility factory remains in source: $symbol."
  fi
done <<'EOF'
makeViewResolver
makeNoOpRenderer
EOF

while IFS= read -r token; do
  [ -z "$token" ] && continue
  if rg -n --glob '*.swift' --fixed-strings --quiet -- "$token" Sources; then
    fail "Retired legacy identifier surface reappeared in source: $token."
  fi
done <<'EOF'
foregroundStyle: String
backgroundStyle: String
borderStyle: String
emphasis: [String]
styleRawValue
RouteID.rawValue
ActionDispatcher
keyboardActionRole
pointerHitPolicy
actionRoutes
actionRole:
focusable(role:
EOF

if ! rg -n --fixed-strings --quiet -- 'extensible style protocols rather than closed public enums' docs/PUBLIC_SURFACE_POLICY.md; then
  fail "docs/PUBLIC_SURFACE_POLICY.md should keep the extensible style-protocol policy."
fi

if ! rg -n --fixed-strings --quiet -- 'New public enum-backed authoring `*Style` surfaces should not be added' docs/PUBLIC_SURFACE_POLICY.md; then
  fail "docs/PUBLIC_SURFACE_POLICY.md should forbid new enum-backed authoring style surfaces."
fi

if ! rg -n --fixed-strings --quiet -- '### Authoring style families' docs/PUBLIC_API_INVENTORY.md; then
  fail "docs/PUBLIC_API_INVENTORY.md should inventory the authoring style families explicitly."
fi

if ! rg -n --fixed-strings --quiet -- 'Protocol-backed style families today' docs/PUBLIC_API_INVENTORY.md; then
  fail "docs/PUBLIC_API_INVENTORY.md should inventory the protocol-backed authoring style families."
fi

if ! rg -n --fixed-strings --quiet -- 'Type-erased style storage' docs/PUBLIC_API_INVENTORY.md; then
  fail "docs/PUBLIC_API_INVENTORY.md should inventory the type-erased style storage values."
fi

if ! rg -n --fixed-strings --quiet -- 'public protocol ToolbarStyle' Sources/View/ActionScopes/Toolbar.swift; then
  fail "ToolbarStyle should stay a public extensible style protocol."
fi

if ! rg -n --fixed-strings --quiet -- 'public protocol ShapeStyle' Sources/Core/Styling.swift; then
  fail "ShapeStyle should stay a public extensible style protocol."
fi

for style_protocol in ButtonStyle TextFieldStyle PickerStyle ListStyle OutlineStyle ToastStyle TabViewStyle; do
  if ! rg -n -P --quiet -- "public protocol ${style_protocol}\\b" Sources/View; then
    fail "${style_protocol} should be a public extensible style protocol in View."
  fi
done

if ! rg -n --fixed-strings --quiet -- 'public protocol TabViewStyle' Sources/View/NavigationViews/TabViewStyles.swift; then
  fail "TabViewStyle should be a public extensible style protocol."
fi

if rg -n -P --quiet -- '(public|package)\s+enum\s+TabViewStyle\b' Sources/View/NavigationViews/TabViewStyles.swift; then
  fail "TabViewStyle must not regress to an enum-owned style surface."
fi

if rg -n -P --quiet -- 'AnyTabViewStyle|AutomaticTabViewStyle|UnderlineTabViewStyle|LiteralTabsTabViewStyle|PowerlineTabViewStyle' Sources/View/NavigationViews/TabView.swift; then
  fail "TabView.swift should not branch directly on built-in tab style types; keep style ownership in TabViewStyles.swift."
fi

if rg -n -P --quiet -- 'switch\s+.*tabStyle|switch\s+.*tabViewStyle' Sources/View/NavigationViews/TabView.swift; then
  fail "TabView.swift should not switch directly on tab styles."
fi

public_style_enums=$(
  rg -n -P --glob '*.swift' -- 'public enum ([A-Za-z_][A-Za-z0-9_]*Style)\b' Sources |
    sed -E 's/.*public enum ([A-Za-z_][A-Za-z0-9_]*Style).*/\1/' |
    LC_ALL=C sort -u
)

for style_enum in $public_style_enums; do
  case "$style_enum" in
  AnyShapeStyle) ;;
  *)
    fail "New public enum-backed *Style surface appeared: $style_enum. Authoring-facing style APIs should prefer public extensible style protocols."
    ;;
  esac
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

while IFS= read -r doc_file; do
  [ -z "$doc_file" ] && continue
  if rg -n -P --quiet -- '(?<!`)``(?!`)' "$doc_file"; then
    fail "$doc_file still contains an empty inline-code runtime placeholder."
  fi
done <<'EOF'
README.md
docs/ARCHITECTURE.md
docs/PUBLIC_API_INVENTORY.md
docs/PUBLIC_SURFACE_POLICY.md
docs/SOURCE_LAYOUT.md
EOF

if ! rg -n --fixed-strings --quiet -- '`SwiftTUI`' README.md; then
  fail "README.md should name SwiftTUI explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '`Runners/SwiftTUICLI`' README.md; then
  fail "README.md should name the SwiftTUICLI runner package explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '`Runners/SwiftTUIWASI`' README.md; then
  fail "README.md should name the SwiftTUIWASI runner package explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '### `SwiftTUI`' docs/PUBLIC_API_INVENTORY.md; then
  fail "docs/PUBLIC_API_INVENTORY.md should classify the SwiftTUI runtime explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '### Peer runner packages' docs/PUBLIC_API_INVENTORY.md; then
  fail "docs/PUBLIC_API_INVENTORY.md should classify the peer runner packages explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '`SwiftTUI` for shared runtime integration plus peer runner packages for executable launch' docs/PUBLIC_SURFACE_POLICY.md; then
  fail "docs/PUBLIC_SURFACE_POLICY.md should describe the library-plus-runner package model explicitly."
fi

if ! rg -n --fixed-strings --quiet -- 'Experimental or showcase targets follow the same rule' docs/PUBLIC_SURFACE_POLICY.md; then
  fail "docs/PUBLIC_SURFACE_POLICY.md should keep the showcase-target policy heading."
fi

if ! rg -n --fixed-strings --quiet -- 'they should not be exported as package products' docs/PUBLIC_SURFACE_POLICY.md; then
  fail "docs/PUBLIC_SURFACE_POLICY.md should keep the showcase export policy."
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi
