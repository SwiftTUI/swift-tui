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
' Sources/SwiftTUIViews/Foundation/ViewFoundation.swift)

if [ -z "$view_protocol_block" ]; then
  fail "Could not isolate the public View protocol block in Sources/SwiftTUIViews/Foundation/ViewFoundation.swift."
else
  case "$view_protocol_block" in
  *"associatedtype Body: View = Never"*)
    fail "The public View protocol must not default Body to Never."
    ;;
  *"associatedtype Body: View"*) ;;
  *) fail "The public View protocol must declare associatedtype Body: View." ;;
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
  Sources/SwiftTUIViews/Foundation/ViewFoundation.swift; then
  fail "The public View protocol must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '@ViewBuilder\s+(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+var body: Body \{ get \}' \
  Sources/SwiftTUIViews/Foundation/ViewFoundation.swift; then
  fail "View.body must stay @ViewBuilder and @MainActor-annotated."
fi

if rg -U -n -P --quiet -- 'extension\s+View\s*(?:where[^{]+)?\{\s*public\s+var\s+body\s*:\s*Never' \
  Sources/SwiftTUIViews; then
  fail "Public primitive body witnesses must not be declared directly on extension View."
fi

if ! rg -U -n -P --quiet -- '(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+public protocol Scene \{' \
  Sources/SwiftTUIRuntime/Scenes/App.swift; then
  fail "The public Scene protocol must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+var body: Body \{ get \}' \
  Sources/SwiftTUIRuntime/Scenes/App.swift; then
  fail "Scene.body must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+public protocol App \{' \
  Sources/SwiftTUIRuntime/Scenes/App.swift; then
  fail "The public App protocol must stay @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- 'nonisolated\s+init\(\)' \
  Sources/SwiftTUIRuntime/Scenes/App.swift; then
  fail "App.init must stay nonisolated so runner/argument protocols can compose with App."
fi

if ! rg -U -n -P --quiet -- '@SceneBuilder\s+(?:@preconcurrency\s+)?@MainActor(?:\s+@preconcurrency)?\s+var body: Body \{ get \}' \
  Sources/SwiftTUIRuntime/Scenes/App.swift; then
  fail "App.body must stay @SceneBuilder and @MainActor-annotated."
fi

if ! rg -U -n -P --quiet -- '@MainActor\s+public func resolve<' \
  Sources/SwiftTUIViews/Foundation/ViewFoundation.swift; then
  fail "Resolver.resolve must stay @MainActor."
fi

if ! rg -U -n -P --quiet -- '@MainActor\s+public func render<' \
  Sources/SwiftTUIRuntime/SwiftTUI.swift; then
  fail "DefaultRenderer.render must stay @MainActor."
fi

if ! rg -U -n -P --quiet -- 'public init\s*\(\s*get: @escaping @MainActor @Sendable \(\) -> Value,\s*set: @escaping @MainActor @Sendable \(Value\) -> Void' \
  Sources/SwiftTUIViews/Foundation/ViewBaseTypes.swift; then
  fail "Binding.init(get:set:) must keep honest @MainActor get/set closures."
fi

if ! rg -n --fixed-strings --quiet -- '@_inheritActorContext' \
  Sources/SwiftTUIViews/Modifiers/ViewLifecycleModifiers.swift; then
  fail "View.task must keep actor-inheriting task closures."
fi

if ! rg -n --fixed-strings --quiet -- 'public func task<ID: Equatable>(' \
  Sources/SwiftTUIViews/Modifiers/ViewLifecycleModifiers.swift; then
  fail "The public task(id:) overload must stay available."
fi

if ! rg -n --fixed-strings --quiet -- 'action: @escaping @MainActor @Sendable () -> Void' \
  Sources/SwiftTUIViews/Controls/Button.swift; then
  fail "Button public actions must stay @MainActor @Sendable."
fi

if ! rg -n --fixed-strings --quiet -- 'private let handler: @MainActor @Sendable (LinkDestination) -> Bool' \
  Sources/SwiftTUIViews/Environment/Environment.swift; then
  fail "OpenLinkAction must stay main-actor-aware."
fi

while IFS= read -r doc_file; do
  [ -z "$doc_file" ] && continue
  if ! rg -n --fixed-strings --quiet -- '@MainActor' "$doc_file"; then
    fail "$doc_file should document the @MainActor authoring model."
  fi
done <<'EOF'
docs/ARCHITECTURE.md
docs/PUBLIC-API.md
Sources/SwiftTUIViews/SwiftTUIViews.docc/Authoring-Views.md
Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Running-Apps.md
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
docs/PUBLIC-API.md
EOF

if [ ! -f Tests/SwiftTUIViewsTests/ActorIsolationSurfaceTests.swift ] && [ ! -f Tests/SwiftTUITests/ActorIsolationSurfaceTests.swift ]; then
  fail "Tests/SwiftTUIViewsTests/ActorIsolationSurfaceTests.swift should exist to pin the actor-isolated surface."
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

while IFS= read -r needle; do
  [ -z "$needle" ] && continue
  if ! rg -n --fixed-strings --quiet -- "$needle" docs/PUBLIC-API.md; then
    fail "docs/PUBLIC-API.md should keep the public-surface policy text: $needle"
  fi
done <<'EOF'
### Authoring style families
extensible style protocols rather than closed public enums
New public enum-backed authoring `*Style` surfaces should not be added
Protocol-backed style families today
Type-erased style storage
## Removed From The Public Surface
## Package-Only Transitional Seams
### `SwiftTUI`
### Root-package platform integration products
Experimental or showcase targets follow the same rule
EOF

if ! rg -n --fixed-strings --quiet -- 'public protocol ToolbarStyle' Sources/SwiftTUIViews/ActionScopes/Toolbar.swift; then
  fail "ToolbarStyle should stay a public extensible style protocol."
fi

if ! rg -n --fixed-strings --quiet -- 'public protocol ShapeStyle' Sources/SwiftTUICore/Styling/ShapeStyles.swift; then
  fail "ShapeStyle should stay a public extensible style protocol."
fi

for style_protocol in ButtonStyle TextFieldStyle PickerStyle ListStyle OutlineStyle ToastStyle TabViewStyle; do
  if ! rg -n -P --quiet -- "public protocol ${style_protocol}\\b" Sources/SwiftTUIViews; then
    fail "${style_protocol} should be a public extensible style protocol in SwiftTUIViews."
  fi
done

if ! rg -n --fixed-strings --quiet -- 'public protocol TabViewStyle' Sources/SwiftTUIViews/NavigationViews/TabViewStyles.swift; then
  fail "TabViewStyle should be a public extensible style protocol."
fi

if rg -n -P --quiet -- '(public|package)\s+enum\s+TabViewStyle\b' Sources/SwiftTUIViews/NavigationViews/TabViewStyles.swift; then
  fail "TabViewStyle must not regress to an enum-owned style surface."
fi

if rg -n -P --quiet -- 'AnyTabViewStyle|AutomaticTabViewStyle|UnderlineTabViewStyle|LiteralTabsTabViewStyle|PowerlineTabViewStyle' Sources/SwiftTUIViews/NavigationViews/TabView.swift; then
  fail "TabView.swift should not branch directly on built-in tab style types; keep style ownership in TabViewStyles.swift."
fi

if rg -n -P --quiet -- 'switch\s+.*tabStyle|switch\s+.*tabViewStyle' Sources/SwiftTUIViews/NavigationViews/TabView.swift; then
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
  LineChartSeriesStyle) ;;
  *)
    fail "New public enum-backed *Style surface appeared: $style_enum. Authoring-facing style APIs should prefer public extensible style protocols."
    ;;
  esac
done

if rg -n --fixed-strings --quiet -- 'These symbols remain public today' docs/PUBLIC-API.md; then
  fail "docs/PUBLIC-API.md still contains outdated migration-era wording."
fi

while IFS= read -r doc_file; do
  [ -z "$doc_file" ] && continue
  if rg -n -P --quiet -- '(?<!`)``(?!`)' "$doc_file"; then
    fail "$doc_file still contains an empty inline-code runtime placeholder."
  fi
done <<'EOF'
README.md
docs/ARCHITECTURE.md
docs/PUBLIC-API.md
docs/RENDER-PIPELINE.md
docs/HOSTS-AND-PLATFORMS.md
EOF

if ! rg -n --fixed-strings --quiet -- '`SwiftTUI`' README.md; then
  fail "README.md should name SwiftTUI explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '`SwiftTUICLI`' README.md; then
  fail "README.md should name the SwiftTUICLI runner product explicitly."
fi

if ! rg -n --fixed-strings --quiet -- '`SwiftTUIWASI`' README.md; then
  fail "README.md should name the SwiftTUIWASI runner product explicitly."
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi
