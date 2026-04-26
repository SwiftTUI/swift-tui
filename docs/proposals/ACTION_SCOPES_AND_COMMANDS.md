# Action Scopes and Commands

**Status:** Landed. The scope scaffolding (`ActionScope`, `AnyID`,
`CommandRegistry`, `Panel` + `.panel(id:)` / `.panel()` / `.focusContainment(_:)`,
`Scene` conformance, presentation-modifier conformances), `.keyCommand(...)`
with shallowest-wins focus-chain dispatch, `.paletteCommand(...)` with
`EnvironmentValues.activePaletteCommands`, and `.toolbar(style:)` plus
`.toolbarItem(...)` are all part of the public `View` surface. See
[ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md](ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md)
for the implementation record.
**Supersedes:** the reverted toolbar/command-palette/help-sheet system (commit `112d98f`, reverted in `076d3e3`)

---

## Context

An earlier implementation of toolbars, command palettes, and help sheets was reverted because the demo app crashed on trivial interactions. The deletion left the framework with two thin keybinding surfaces that don't compose cleanly:

- `.onKeyPress()` → public modifier writing into a global `HotkeyRegistry`. Fires only while the authoring view is resolved. The modifier syntax implies locality but the semantics depend on tree-stable placement. Consumers who co-locate the handler with the view it logically belongs to write fragile bindings.
- `LocalKeyHandlerRegistry` → package-internal, focus-identity-keyed, used by built-in controls (List, Picker, TabView, Stepper, TextField) for single-key widget behavior.

Neither corresponds to how users think about command availability. Users think about **what they can do right now**, which is determined by what part of the app they're in, what's focused, and what's selected — not "which view is rendering."

This proposal introduces a single abstraction — the **ActionScope** — that captures all of these, together with the API for declaring commands, toolbars, and toolbar items against it.

## Principles

1. **App Navigation ⊂ Modal App Behavior ⊂ Scopes.** Navigation is one disciplined kind of mode; modes are a subset of scopes. Scopes are the primitive.
2. **The focus chain is the activation predicate.** A scope is active iff its anchor node is on the current focus chain. Tree presence is a prerequisite; focus-chain membership is the activation condition.
3. **Commands are declared at the scope root.** They are not hoisted from descendants. Deep views do not have authority to inject into scope-level command surfaces.
4. **Toolbar items are hoisted from descendants.** They are a local UI contribution, not a scope-level claim. They land in the nearest ancestor ActionScope that has declared a toolbar surface.
5. **Shallower wins on key collisions.** Authority lives at authorial scopes. Deep dependencies cannot silently override shortcuts claimed higher up.
6. **Framework reserves single-key handling.** Only `modifier + key` bindings are exposed to consumer API. Typing, arrow-key navigation, Tab, Enter, and Escape are framework-owned and routed internally to focused widgets.
7. **Discoverability is consumer-wrapped.** The framework does not ship a palette or help overlay. Consumers declare surfaces; the framework provides the annotations they consume.

## Core Abstractions

### `ActionScope`

```swift
public protocol ActionScope: Identifiable {
  associatedtype ID: Hashable & Sendable
}
```

An ActionScope is a tree-authored focus region that owns a set of commands. Conformance is deliberate and implies:

- The node participates in the focus topology at least as strongly as a focus section (SwiftUI-equivalent).
- The framework can ask "is this scope on the current focus chain?" and get a definite answer.
- The scope carries a stable identity usable for enumeration, discoverability, and dispatch.

Existing DSL nodes gain conformance:

- Scene-conforming types (e.g., `WindowGroup`) → `ActionScope.ID` aliases `WindowIdentifier` (or equivalent scene identity already present on the type).
- The presentation modifiers behind `.sheet()`, `.alert()`, `.confirmationDialog()` → conform; IDs alias existing presentation coordinator tokens.
- `NavigationStack` destinations (future; deferred pending NavigationStack landing) → conforming naturally per destination.

A plain `View` does not conform. Scope-ness is opt-in.

### The focus chain

There is always a focus chain from the root of the scene down to whichever leaf currently owns focus. Every node on the chain is reachable by input; every node off it is silent. "Is a scope active?" reduces to "is its anchor on the chain?"

For structural scopes, the anchor is the DSL node itself (Scene, sheet, Panel). For Panel specifically, the anchor is considered on the chain when focus is within the Panel's geometric bounds or on the Panel itself.

### Scope kinds

Three concrete kinds in this design:

| Kind | Anchor | Identity | Notes |
|---|---|---|---|
| **Scene** | `Scene` instance | `WindowIdentifier` alias | Root-most scope; trivially on the chain while the scene is active |
| **Presentation** | `.sheet` / `.alert` / `.confirmationDialog` modifier | Presentation coordinator token alias | Active while the presentation is on screen |
| **Panel** | `Panel` view | User-provided `Hashable & Sendable` or framework-derived | Consumer-declared, rectangular, focus-contained |

Notably absent: Selection-scope. Selection is expressed as a predicate on commands (`isEnabled:`), not as a distinct scope kind. This keeps the scope-kind set small and preserves the "every scope is a focus region" invariant.

## Public API Surface

### `Panel`

The consumer-facing primitive for "I want an ActionScope here."

```swift
public struct Panel<ID: Hashable & Sendable, Content: View>: View, ActionScope {
  public init(id: ID, @ViewBuilder content: () -> Content)
}

/// A type-erased Hashable & Sendable identity. Used as Panel's ID type when
/// the consumer doesn't supply an explicit identity. The framework populates
/// it from the structural identity path at the call site.
public struct AnyID: Hashable, Sendable {
  internal init(_ value: some Hashable & Sendable)
}

extension View {
  /// Wraps `self` in a Panel with an explicit identity.
  public func panel<ID: Hashable & Sendable>(id: ID) -> Panel<ID, Self>

  /// Wraps `self` in a Panel whose identity is derived from the structural
  /// identity path at the call site. Stable across re-resolves; reproduced
  /// deterministically per source location and surrounding identity context.
  public func panel() -> Panel<AnyID, Self>
}
```

`AnyID`'s initializer is `internal` to this package for now — consumers should use `.panel(id:)` with their own `Hashable & Sendable` values rather than constructing `AnyID` directly. The type exists to give the pseudonymous-Panel variant a nameable return type while keeping the actual identity derivation a framework concern.

Panel has **no default UI chrome**. It is a pure focus/scope primitive; visual treatment is the consumer's responsibility via standard modifiers (`.border`, `.background`, `.padding`, etc.).

#### Focus semantics

- A Panel is always focusable.
- When a Panel enters the focus chain (via presentation, navigation, or explicit focus request), the Panel itself is focused first — not a descendant — unless descendant focus is explicitly requested.
- Default: Tab moves focus through the Panel's focusable descendants.
- Opt-in: `.focusContainment(.sealed)` on a Panel makes Tab skip its descendants. Descendants are reachable only via explicit drill-in (a mechanism reserved for future design; sealed Panels are opaque to Tab traversal until then).

```swift
extension Panel {
  public func focusContainment(_ mode: FocusContainment) -> Panel<ID, Content>
}

public enum FocusContainment: Sendable {
  case open    // default: Tab reaches descendants
  case sealed  // Tab skips descendants; Panel is the focus stop
}
```

### Commands (scope-root only)

Commands are declared by applying modifiers to an ActionScope. The framework requires the receiver of these modifiers to conform to `ActionScope` — this is enforced at the type level.

```swift
extension ActionScope where Self: View {
  public func keyCommand(
    _ description: String,
    key: KeyEvent,
    modifiers: EventModifiers,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View

  public func paletteCommand(
    name: String,
    description: String? = nil,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View
}
```

#### `keyCommand` rules

- `modifiers` **must be non-empty**. Single-key shortcuts are compile-time or runtime rejected. (Implementation decides which; runtime precondition is acceptable for v1.)
- A scope may declare multiple `keyCommand`s. Two declarations on the same scope with the same `(key, modifiers)` pair are considered authoring errors; the framework emits a diagnostic and the last declaration wins.
- `isEnabled: false` does **not** remove the claim. The command still appears in discoverability surfaces (rendered disabled) and still blocks deeper scopes from claiming the same shortcut.

#### `paletteCommand` rules

- No key binding involved. This is pure metadata + action.
- Multiple palette commands with the same `name` at different scopes are allowed; a palette surface is responsible for its own de-duplication or disambiguation policy.
- `isEnabled: false` shows the command as disabled in palette surfaces; activating it is a no-op.

### Toolbar surface (scope-root only)

```swift
public protocol ToolbarStyle {
  /// The layout type used to arrange toolbar items. Reuses the framework's
  /// existing `Layout` protocol so toolbars compose with standard layout
  /// machinery.
  associatedtype Layout: TerminalUI.Layout
}

public struct DefaultTopToolbarStyle: ToolbarStyle { /* uses HStack-equivalent Layout */ }
public struct DefaultBottomToolbarStyle: ToolbarStyle { /* uses HStack-equivalent Layout */ }

extension ActionScope where Self: View {
  /// Declares that this scope has a toolbar. Items hoisted from descendants
  /// (via `.toolbarItem(_:)`) land here.
  public func toolbar<S: ToolbarStyle>(style: S) -> some View
}
```

The styling surface (colors, separators, spacing) is left to implementation; the protocol above is the minimum contract. `ToolbarStyle`'s layout type determines how items flow (horizontally, wrapped, etc.) by reusing the framework's existing `Layout` protocol.

A scope that has not called `.toolbar(style:)` does not absorb toolbar items. Items hoisted from its subtree pass through to the next enclosing ancestor that *does* have a toolbar. If no ancestor has a toolbar, items are silently ignored (no-op). This mirrors how `.paletteCommand` behaves when no palette surface exists.

### Toolbar items (hoisted from any view)

```swift
public struct ToolbarItemConfig: Sendable {
  public enum Position: Sendable { case top, bottom, automatic }
  public var title: String
  public var icon: Image?
  public var position: Position
  public var isEnabled: Bool
  public var action: @MainActor @Sendable () -> Void
}

extension View {
  public func toolbarItem(_ config: ToolbarItemConfig) -> some View

  /// Builder-based variant for fully custom label/icon.
  public func toolbarItem<Label: View, Icon: View>(
    position: ToolbarItemConfig.Position = .automatic,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void,
    @ViewBuilder label: () -> Label,
    @ViewBuilder icon: () -> Icon
  ) -> some View
}
```

Any view may contribute a toolbar item. The framework collects contributions via the preference-key mechanism and delivers them to the nearest ancestor ActionScope that has a toolbar.

## Semantics

### Key dispatch and precedence

On a key press with at least one modifier:

1. The framework walks the current focus chain from **root to leaf** (shallowest first).
2. At each scope on the chain, it looks for a `keyCommand` declaration matching `(key, modifiers)`.
3. The first match wins. If that match is `isEnabled: true`, its action fires. If `isEnabled: false`, the key press is consumed but no action runs. In both cases, dispatch halts.
4. If no scope on the chain declares the binding, the key press is ignored.

This is strict shallowest-wins. Absence is permission for deeper scopes to claim a binding; presence (even disabled) is an authoritative claim.

### Single-key dispatch (framework-owned)

Single-key events (no modifier, or Shift-only letters treated as typing) are routed internally:

- Typing is delivered to the deepest focused text-editing widget, if any.
- Arrow keys, Tab, Shift+Tab, Enter, and Escape are routed per existing `LocalKeyHandlerRegistry` semantics: the deepest focused widget handles them, or focus traversal policy takes over.
- Consumers cannot register handlers for single-key events via public API.

### Toolbar item hoisting

Hoisting uses the existing preference-key infrastructure. A `.toolbarItem(...)` modifier contributes to a `ToolbarItemsPreferenceKey` whose value accumulates up the tree. At each ActionScope boundary, the framework checks whether a toolbar was declared on that scope. If so, it consumes the accumulated items; if not, items continue upward. This produces the "nearest ancestor with a toolbar" semantics without special-case machinery.

### `isEnabled` rendering

`isEnabled: false` does not affect visibility in any discoverability surface. Disabled commands still appear in palettes, toolbars, and help overlays. Rendering applies a disabled style (reduced opacity, greyed text, or whatever the surface's convention is). Activation (via key or click) is a no-op when disabled.

## Discoverability

The framework does not ship a palette view or a help overlay. It does provide the annotation and collection mechanisms that consumer-authored surfaces can query.

Expected consumer patterns:

```swift
// Consumer palette wraps the UI and queries active palette commands.
PaletteContainer {
  AppContent()
}

// A consumer-authored PaletteContainer reads active scope's paletteCommands
// (via an environment value or query API), renders them when presented,
// and dispatches the selected command's action.
```

The specific query API (e.g., `@Environment(\.activePaletteCommands)` or similar) is deferred to implementation. The guarantee is: declarations always succeed; consumption is optional; absent-consumer = inert-declaration.

## Rewrite scope

### Removed (public surface)

- `.onKeyPress(...)` modifier (both variants in `Sources/View/Modifiers/OnKeyPress.swift`) — deleted. No migration path; consumers must rewrite to `keyCommand` attached to a scope root.

### Removed (package-internal surface)

- `HotkeyRegistry` (`Sources/Core/HotkeyRegistry.swift`) — deleted. All of its callers currently go through `.onKeyPress`.
- `HotkeyBinding`, `HotkeyRegistrationSnapshot` — deleted with the registry.
- The `hotkeyRegistry` field on `RunLoop` and `RuntimeRegistrationSet` — removed.

### Renamed / refocused

- `LocalKeyHandlerRegistry` remains package-internal. It becomes the single-key dispatch engine exclusively, used by built-in controls. Consider renaming to `SingleKeyDispatch` or similar for clarity; final naming during implementation.

### Added (public surface)

- `ActionScope` protocol
- `Panel` view + `.panel()` / `.panel(id:)` modifiers
- `FocusContainment` enum + `.focusContainment(_:)` on Panel
- `.keyCommand(...)` and `.paletteCommand(...)` on `ActionScope where Self: View`
- `.toolbar(style:)` on `ActionScope where Self: View`
- `.toolbarItem(...)` on any View
- `ToolbarItemConfig`, `ToolbarStyle`, default styles

### Added (conformances)

- `Scene` conforms to `ActionScope`
- `.sheet()`, `.alert()`, `.confirmationDialog()` presentation modifiers conform to `ActionScope`

### Built-in controls

No public API change. Internal key handling (arrows in List/Picker/TabView/Stepper, typing in TextField) continues via the single-key dispatch engine.

## Out of scope / deferred

- **NavigationStack integration.** NavigationStack is explicitly deferred in VISION.md. When it lands, each pushed destination should conform to ActionScope. Nothing about this design blocks that; it's purely additive.
- **Default palette/help surfaces.** Framework does not ship these. Consumers write their own.
- **Drill-in from sealed Panels.** A `.focusContainment(.sealed)` Panel can be focused as a unit but descendants aren't Tab-reachable. A future design will add an explicit drill-in mechanism (keybinding, modifier to permit descendant entry on activation). For v1, sealed Panels are opaque to Tab.
- **Multi-key chords** (e.g., `Ctrl+K, Ctrl+S`). Not supported. Can be added later as an extension of `keyCommand` without breaking existing surface.
- **Platform menu bar integration.** If macOS or similar hosts later want to surface `paletteCommand` declarations as native menu items, that's a host-integration concern, not a framework concern.
- **Command groups/categories.** `paletteCommand` currently carries only name + description. A future enhancement could add group metadata for palette organization.

## Open questions

None blocking. The following may surface during implementation:

- Final name for the renamed single-key dispatch engine (`LocalKeyHandlerRegistry` → ?).
- Final shape of the `ToolbarStyle` layout protocol.
- Final shape of the consumer-side query API for palette/help surfaces.

These are implementation-phase decisions; the spec above does not depend on their outcomes.

## Design sequence (how this was reached)

For posterity. The abstraction sequence that produced this design:

1. Observation: `.onKeyPress()` is a view modifier but its semantics require tree-stable placement. Locality is promised and denied.
2. Generalization: navigation is a special case of modes; modes are a special case of scopes.
3. Activation predicate: not "is the anchor resolved?" but "is the anchor on the focus chain?" Presence without reachability is silent.
4. Scope kinds: collapse from five to three by making Selection a predicate, not a kind. Every ActionScope is a focus region.
5. Authoring asymmetry: commands are top-down (scope-root authored), toolbar items are bottom-up (hoisted). Each direction has a different authority argument.
6. Precedence: shallowest-wins. Authorship authority lives at shallow scopes; deep dependencies cannot silently override.
7. Single-key reservation: framework-owned, consumer API accepts only modifier+key. Eliminates typing/shortcut ambiguity entirely.
8. Discoverability: consumer-wrapped, not framework-shipped. Declarations succeed unconditionally; consumption is optional.

Each step simplified the model. The final design has no moving parts that aren't load-bearing.
