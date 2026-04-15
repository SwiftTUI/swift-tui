# Commands & Chrome — Design Proposal

> Status: **Landed in Milestone 8.** See sections below for the design
> intent; call-outs note where the landed implementation diverged from
> the proposal. Supersedes the earlier `TOOLBAR_API.md` draft, which
> conflated two distinct concerns into a single surface.
> Audience: maintainers of swift-terminal-ui considering ergonomic
> public surfaces for actions, key bindings, status chrome, help
> discoverability, and the existing command palette.
> Companion documents: [VISION.md](../VISION.md) (Confirmed Deviations,
> Input Philosophy, Prototype-First items),
> [LIPGLOSS_SWIFTUI_EQUIVALENTS.md](../LIPGLOSS_SWIFTUI_EQUIVALENTS.md),
> [SHAPE_AND_BORDER_APIS.md](SHAPE_AND_BORDER_APIS.md) (precedent for
> "rationalize a chrome surface against the existing infrastructure").

## 1. Why this exists

This proposal rationalizes four surfaces that today exist in
TerminalUI as disconnected fragments, and ships the missing pieces as
a single coherent system:

1. The **command model** (`Command`,
   `Sources/View/Presentation/CommandPalette.swift:6-89`) — semantic
   action entries with id, title, kind, disabled state, used today
   only by the command palette.
2. The **hotkey registry** (`HotkeyRegistry`,
   `Sources/Core/HotkeyRegistry.swift:1-119`) — focus-independent
   key dispatch with binding records that *already* carry a `label`
   and a `group` field for help display, but with no public
   authoring path that fills those fields and no public renderer
   that reads them.
3. The **command palette**
   (`Sources/View/Presentation/CommandPalette.swift:374-660`) — a
   searchable sheet auto-populated from `.command(...)` registrations
   in the focused subtree. Already shipped, already used.
4. The **prototype help strip**
   (`Sources/PrototypeUIComponents/PrototypeSurfaces.swift:5-21`,
   `Sources/PrototypeUIComponents/PrototypeModels.swift:1-40`) — an
   exploration that proves the rendering layout for an `[^S] Save`
   bottom strip works, but forces the author to pass a hand-curated
   `[PrototypeKeyBinding]` array parallel to the real handlers.

These pieces are obviously meant to fit together. Today they don't.

The first draft of this proposal tried to fix that by introducing a
`.toolbar { ToolbarItem(key: .ctrl("s"), …) }` API where the toolbar
item carried the key binding. That framing was wrong. **Author-placed
chrome and binding-derived discoverability are two different
concerns**, and conflating them produces the same kind of footgun that
SHAPE_AND_BORDER_APIS.md§1 documents for `.border` overdrawing
content: a single surface trying to do two jobs ends up doing both
poorly.

The corrected framing is one model and three lenses:

```
                ┌──────────────────────────────┐
                │      Command (the noun)      │
                │  id · title · key · group    │
                │  kind · isDisabled · action  │
                └──────────────────────────────┘
                  ▲                ▲          ▲
                  │ refers to      │ derived  │ derived
                  │                │ from     │ from
       ┌──────────┴────┐  ┌────────┴───┐  ┌───┴────────┐
       │   Toolbar     │  │    Help    │  │  Command   │
       │   (author-    │  │  (auto-    │  │  Palette   │
       │   placed)     │  │  derived)  │  │ (existing) │
       └───────────────┘  └────────────┘  └────────────┘
```

- `Command` is the data model. An author registers a command once,
  optionally with a key binding, optionally in a group, with an
  action.
- The **Toolbar** lens lets the author *explicitly place* chrome —
  status indicators, mode badges, inline progress, the right-docked
  primary action — in the same SwiftUI-shaped `.toolbar { … }`
  result-builder syntax that desktop SwiftUI uses. Toolbar items can
  refer to commands by id to share their title / key / disabled
  state, but the toolbar never *auto-derives* its contents from the
  registry.
- The **Help** lens *auto-derives* a presentation of registered
  commands in the focused scope, in two forms: a condensed inline
  strip (the bottom-row F-key footer) and an expanded sheet
  (the `?`-triggered cheatsheet, grouped by `Command.group`). This
  is the part the previous draft mislabeled as "the toolbar's
  auto-register-and-render behavior." It isn't. It's a help system.
- The **Command Palette** is the existing fuzzy-searchable sheet
  (`.commandPalette(isPresented:)`) that already reads the same
  command preference key. It needs no API changes; it picks up the
  unified `Command` automatically and gains key-glyph rendering as a
  small visual enhancement.

Authors writing a non-trivial TUI today must pick one of these and
forgo the others. Authors writing a non-trivial TUI under this
proposal write `.command(…, key: .ctrl("s")) { save() }` once and
get all four behaviors:

- focus-independent shortcut dispatch
- discoverability via the help strip and `?` help sheet
- discoverability via the existing command palette
- the option to surface in the toolbar by `id` reference

The conditions VISION.md sets for landing terminal-native help and
keybinding surfaces — that the interaction model is clear and the
API still reads like the same SwiftUI-shaped product
(`docs/VISION.md:79-86`) — are met. The runtime cost is bounded:
no new registry, no new layout primitive, no new pointer routing.

## 2. What we already have (inventory)

Everything this proposal builds on, with file references so the
review can sanity-check the seams.

**The command model (public)**
`Sources/View/Presentation/CommandPalette.swift:6-89`

```swift
public struct Command: Hashable, Sendable, Identifiable {
  public enum Kind { case action, navigation, toggle, destructive }
  public var id: String
  public var title: String
  public var detail: String?
  public var keywords: [String]
  public var kind: Kind
  public var isDisabled: Bool
  // No `key`. No `group`. Both are needed for the help system.
}
```

**The command authoring modifier (public)**
`Sources/View/Presentation/CommandPalette.swift:271-329`

```swift
extension View {
  public func command(id:title:detail:keywords:kind:isDisabled:) -> some View
  public func command(id:title:..., action: @escaping @MainActor @Sendable () -> Void) -> some View
}
```

The action overload exists, takes an authoring-context-aware
trampoline (`CommandPalette.swift:332-363`). It does not yet take a
key binding — adding one is the central change in this proposal.

**The hotkey binding model (package-internal)**
`Sources/Core/HotkeyRegistry.swift:1-19`

```swift
package struct HotkeyBinding: Equatable, Sendable {
  package var key: KeyPress
  package var label: String     // ← already exists for help display
  package var group: String?    // ← already exists for help display
  package var commandID: String?// ← already names the bridge to Command
}
```

`HotkeyBinding` is a `Command` in disguise — its fields are exactly
the missing fields plus the key. The unified design hoists key/
group/label into `Command` and demotes `HotkeyBinding` to a
package-internal projection of an active command.

**The hotkey registry (package-internal, lifecycle-managed)**
`Sources/Core/HotkeyRegistry.swift:46-118`

```swift
@MainActor package final class HotkeyRegistry {
  package func register(identity:binding:handler:)
  package func dispatch(_ keyPress: KeyPress) -> Bool
  package func registeredBindings() -> [HotkeyBinding]    // ← seam for the help renderer
  package func removeSubtrees(rootedAt: [Identity])       // ← lifecycle for unmount
  package func snapshot() / restore(_:)                   // ← lifecycle for focus shifts
}
```

`registeredBindings()` is the read-side seam a help strip would call.
`removeSubtrees(rootedAt:)` is the lifecycle hook that already
handles the "stale binding when focus scope unmounts" problem.

**The command preference key (private but load-bearing)**
`Sources/View/Presentation/CommandPalette.swift:248-258`

```swift
private enum CommandPreferenceKey: PreferenceKey {
  static let defaultValue = CommandPreferenceValue()
  static func reduce(value: inout CommandPreferenceValue,
                     nextValue: () -> CommandPreferenceValue) {
    value.registrations.append(contentsOf: nextValue().registrations)
  }
}
```

Every `.command(...)` declaration writes a record into this preference
key and the value flows up the tree via the existing reduction. The
command palette already reads from it
(`CommandPalette.swift:692-717`). The help system will read from
the same key. The toolbar will read from it for `commandID:`-bound
items. **No new preference flavor is needed.**

**The command palette (public, shipped)**
`Sources/View/Presentation/CommandPalette.swift:374-660`

```swift
public func commandPalette(
  isPresented: Binding<Bool>,
  placeholder: String = "Search commands…",
  shortcut: KeyEvent? = nil,
  shortcutModifiers: EventModifiers = [],
  onExecute: @escaping @MainActor @Sendable (Command) -> Void = { _ in }
) -> some View
```

Already presents a sheet auto-populated from `CommandPreferenceKey`
registrations in the subtree. Nothing about this surface needs to
change. It picks up the `key` and `group` additions to `Command`
automatically and renders them as small visual enhancements.

**Pointer routing for clickable affordances**
`Sources/View/NavigationViews/TabView.swift:120-139`

`PointerRouteView` plus `localPointerHandlerRegistry?.register(routeID:)`
is the existing path that lets a non-focusable visual element route
clicks back to a registered handler. The TabView tab strip uses it
today; a help strip's clickable key glyphs and a toolbar item's
clickable affordance both reuse the same path.

**Decoration-layout reservation**
`Sources/View/Modifiers/Preference.swift:111-148`,
`Sources/View/Modifiers/StyleModifiers.swift:121-195`

`overlayPreferenceValue(...)` returns a `ResolvedNode` with
`layoutBehavior: .decoration(primaryIndex:alignment:)`. The border
revamp uses the same path so border glyphs live in reserved frame
insets rather than overdrawing content
(`docs/proposals/SHAPE_AND_BORDER_APIS.md:18-58`). Both the toolbar
and the help strip will use the same mechanism for the same reason:
their rows must be reserved insets, not content overdraw.

**Prototype prior art**
`Sources/PrototypeUIComponents/PrototypeSurfaces.swift`,
`Sources/PrototypeUIComponents/PrototypeModels.swift`

`PrototypeHelpSurface` proves the help strip rendering layout works.
This is the shape this proposal subsumes into the public help
system; the prototype gets deleted once the public surface lands.

**What is *not* present and is out of scope to add here**

- `safeAreaInset(...)` — the existing decoration-layout path is
  enough.
- A general `.keyboardShortcut(_:modifiers:)` view modifier — this
  proposal's keyboard story flows through `.command(..., key: …)`.
  A bare `.keyboardShortcut(...)` for buttons-without-commands can
  land later without disturbing this design.
- `NavigationStack` — VISION.md keeps this deferred
  (`docs/VISION.md:75-78`); the toolbar must not require it.

## 3. Lessons from other ecosystems

A wider survey of how real TUIs and SwiftUI handle these four
concerns. The full notes are summarized inline; the load-bearing
observations only.

### 3.1 SwiftUI

The relevant surface for the **toolbar** lens:

```swift
.toolbar { @ToolbarContentBuilder content: () -> some ToolbarContent }
```

with `ToolbarContent` as a protocol with associatedtype `Body`,
`@ToolbarContentBuilder` as the result builder, and primitives
`ToolbarItem(placement:, content:)`,
`ToolbarItemGroup(placement:, content:)`,
`ToolbarSpacer(_:placement:)`. Items are placed by
`ToolbarItemPlacement` cases, with a separate `ToolbarPlacement`
namespace for bar visibility (`.toolbarBackground`,
`.toolbar(_ visibility:for:)`).

**SwiftUI has no help system.** `.keyboardShortcut(_:modifiers:)`
attaches a shortcut to a button without ever rendering a visible
hint anywhere — desktop apps surface shortcuts in the menu bar, and
SwiftUI relies on that. The visible-shortcut story is *exactly* the
gap the TUI needs to fill. **This is the load-bearing observation
that pushes the binding-derived strip out of the toolbar and into a
dedicated help system.**

**The parts of SwiftUI's toolbar surface that survive a TUI port
verbatim**: the result-builder shape, the `ToolbarContent` protocol
with associatedtype `Body`, `ToolbarItem` wrapping a real `View`
body, `ToolbarItemGroup` for shared placement, `ToolbarSpacer`,
the two-namespace split between item placement and bar visibility,
and the `Visibility`-per-bar control.

**The parts that should not survive**: `ToolbarRole` (iPad-only
nav-bar layout hinting), `ToolbarTitleMenu` and
`.toolbarTitleDisplayMode` (presuppose titled chrome), the entire
`CustomizableToolbarContent` / `id:` / `showsByDefault` story (no
drag-to-rearrange affordance in a TUI), and the placement cases
that depend on chrome the framework does not render.

### 3.2 Textual (Python) — the help-system gold standard

The reference implementation for "declare bindings once, render
visible discoverability automatically." A `Screen` declares
class-level `BINDINGS`:

```python
BINDINGS = [
  Binding("ctrl+s", "save", "Save"),
  Binding("ctrl+q", "quit", "Quit", group="Session"),
]
```

A docked `Footer` widget reads `screen.active_bindings` from the
focused screen and renders the strip *automatically*. Pressing `?`
opens the equivalent expanded view. Critical properties of this
help-system model that the proposal copies:

1. **One declaration drives input dispatch and all visible
   discoverability surfaces.** No drift between handlers and labels.
2. **Deduplication by `action` (i.e. command id), not by key.**
   When the same action is bound to multiple keys, only one entry
   renders; the framework picks the canonical first key.
3. **Active set is focus-/scope-dependent.** As focus moves between
   screens, `active_bindings` re-walks the focused tree and the
   strip recomposes via a `bindings_updated_signal`.
4. **Disabled is first-class.** Disabled bindings render dim, in
   place, instead of disappearing — overflow stays stable.
5. **Click on the affordance synthesizes the keypress.**
   `FooterKey.on_mouse_down` calls `self.app.simulate_key(self.key)`.
6. **Right-docked primary action slot.** `show_command_palette` is
   docked right with a vertical separator. This slot is for the
   *toolbar*, not the help strip, even though Textual renders them
   in the same row — Textual conflates them visually but the
   conceptual split is still observable in the source.
7. **Overflow is horizontal scroll** (the `Footer` extends a
   `ScrollableContainer`).

Textual's `BINDINGS` declaration is the single best ergonomic
benchmark in any TUI ecosystem for this proposal. The proposal's
unified `.command(..., key:) { … }` modifier is its direct
analogue.

### 3.3 Charm Bubble Tea + bubbles/key + bubbles/help

The strongest non-Python reference. A `key.Binding` carries both
`Keys` and `Help{Key, Desc}`, and a model implements the `KeyMap`
interface:

```go
ShortHelp() []key.Binding        // single-line strip
FullHelp() [][]key.Binding       // grid for `?` expanded help
```

`help.Model.ShortHelpView` renders with `" • "` separators and
truncates with an ellipsis when the strip exceeds `SetWidth`.
Disabled bindings (via `SetEnabled(false)`) are automatically
hidden from help. The package is *literally named `help`* — not
"toolbar," not "footer," not "statusbar." That naming is correct
and the proposal follows it.

Real apps (e.g. `soft-serve`'s `pkg/ui/pages/repo/repo.go`) merge
per-pane bindings with global bindings — the same scope-merge
pattern the proposal needs to support through focus-scoped
preference reads.

### 3.4 Real apps — the toolbar-vs-help split, observable in the wild

When you look at real TUIs through the "one model, three lenses"
frame, the split between **author-placed chrome** and
**auto-derived help** is everywhere:

- **htop / nano / Midnight Commander** — bottom F-key footer is a
  *help system* (auto-derived, key-shaped, mode-dependent labels).
  These apps have no separately authored toolbar; the help strip
  is the only chrome.
- **lazygit** — bottom *information line* is *toolbar* (mode
  badge, version, donate links, hand-curated). Per-panel hint
  labels are *help* (mode-dependent, declared alongside handlers).
  The `?` cheatsheet is *help expanded view*. Three surfaces, one
  app, distinct concerns.
- **k9s** — top breadcrumbs are *toolbar*. Bottom `Menu` (rebuilt
  on `StackPushed/Popped` from `Component.Hints()`) is *help*.
- **helix** — `[editor.statusline]` config slots are *toolbar*
  (mode, file-name, diagnostics, position — author-placed). The
  space-mode which-key popover is *help expanded view*. There is
  no condensed help strip; helix relies entirely on the popover
  for discovery.
- **vim/neovim** — format-string statusline is *toolbar*.
  `which-key.nvim` is *help expanded view*. Same split as helix.
- **fzf** — `--header` is *toolbar*. `--bind` flags are
  shortcut-only (no help affordance); fzf has no help system at
  all and the `?` key is unbound by default.
- **tig / btop / gitui** — manual bottom hint strips that mix both
  concerns, hand-synced with handlers. The cautionary tale.

**Cross-cutting patterns** that shape the API:

1. **Bottom is the default** for help strips. Top is reserved for
   tabs, breadcrumbs, and titles. The proposal defaults the help
   strip to the bottom row and leaves the top free for `TabView`.
2. **Toolbar and help can occupy the same physical row** (Textual,
   lazygit) but they are *conceptually different surfaces* and
   should compose, not collapse into each other. The proposal
   models them as two distinct presentation lenses that the host
   row may render adjacent to each other.
3. **Mode/scope dependence is universal.** The help strip always
   reflects the focused subtree, not the whole tree. The proposal
   uses the existing focus + preference reduction model, which
   already provides this.
4. **Three help-rendering idioms coexist** in real apps: the F-key
   footer (htop / mc / Textual), the bracketed inline
   `[s]ave [q]uit` (Charm short help, gitui), and the which-key
   popover (helix space-mode). The first two are the **condensed
   help strip**. The third is the **expanded help sheet**. Both
   are part of v1; the popover style is just a different
   rendering of the same data the sheet uses.
5. **When an action has multiple keys, the canonical first one
   wins the help label**. The proposal dedupes by `Command.id`,
   not by `KeyPress`.
6. **Disabled-but-visible is first-class** for help strips — hiding
   produces layout jitter. The proposal dims, not hides.
7. **Overflow has three real-world strategies**: ellipsis
   truncation (Charm), horizontal scroll (Textual), multi-row
   wrap (k9s). The proposal offers all three through a single
   `.helpStripOverflow(...)` modifier.
8. **Click-on-affordance equals pressing the key** for help
   affordances in Textual and mc. The proposal makes this the
   default by reusing `PointerRouteView`.

## 4. Proposed unified design

### 4.1 The data model

Extend `Command` to absorb the help-display fields that
`HotkeyBinding` already has, plus the key itself.

```swift
public struct Command: Hashable, Sendable, Identifiable {
  public enum Kind: Hashable, Sendable {
    case action
    case navigation
    case toggle
    case destructive
  }

  public var id: String
  public var title: String
  public var detail: String?
  public var keywords: [String]
  public var kind: Kind
  public var isDisabled: Bool

  // New fields (folded in from HotkeyBinding):
  public var key: KeyPress?     // optional canonical key binding
  public var group: String?     // help-section grouping ("Document", "View", …)
}
```

`HotkeyBinding` is demoted to a package-internal projection of an
active command — the type still exists as the registry's record
shape, but `Command` is the public name and the public authoring
target. Every field in `HotkeyBinding` is now derivable from a
`Command`.

**Compatibility note**: the existing `Command(id:title:...)` public
initializer keeps its behavior; the new fields default to `nil`.
Existing call sites continue to compile and continue to write into
the command preference key as they do today.

### 4.2 Command registration: two tiers and why

A footgun to surface up front before describing the API.

Because `.command(...)` registers only while the view it's attached
to is evaluated in the body hierarchy, an author can accidentally
hide a command behind a conditional:

```swift
var body: some View {
  VStack {
    if showAdvanced {
      AdvancedPanel()
        .command(id: "foo", title: "Foo", key: .ctrl("f")) { … }
    }
    MainPanel()
  }
}
```

Here `Ctrl+F` dispatches only while `showAdvanced` is true. That is
the *right* behavior when `foo` is genuinely scope-dependent — but
it is the *wrong* default when the author meant "always on and I
just tucked the registration into whichever view felt convenient."
In a TUI where the help system auto-renders visible affordances, a
flickering command is visibly broken: it appears in the strip only
when its owning view is evaluated, and disappears the instant the
view's enclosing conditional flips.

SwiftUI mitigates the analogous `.toolbar` footgun with two features
that TerminalUI does *not* need to copy wholesale:

1. **`NavigationStack`**, which gives you a natural "current route"
   whose toolbar is always evaluated. The proposal **deliberately
   does not introduce `NavigationStack` to solve this problem**.
   `NavigationStack` is deferred by VISION.md for unrelated reasons
   (`docs/VISION.md:75-78`); it is a much larger API whose primary
   value propositions are orthogonal to command scope; and it does
   not actually eliminate the footgun because the same flickering-
   conditional pattern can still happen *inside* a single screen's
   body. Introducing a stack to fix a scope footgun is a mismatched
   hammer, and TUI apps are more often panel-shaped (lazygit, k9s,
   helix) than stack-shaped anyway.

2. **`App.commands { … }`**, the menu-bar slot on `App`, which is
   always evaluated for the lifetime of the app regardless of which
   views are rendered. **This is the lever TerminalUI should copy.**
   It is a much smaller API, it hangs off the scene rather than the
   body, and it inverts the ergonomic default: the first place an
   author reaches to register a command is an always-evaluated
   slot, and view-level scoping becomes a conscious opt-in.

So the proposal introduces **two tiers** of command registration,
and positions them with a clear default:

- **Scene-level `.commands { … }` (§4.2.1) — the primary,
  prominent registration site.** Commands declared here are
  registered for the lifetime of the scene, independent of which
  views inside the scene are currently rendered. This is the
  natural home for always-on actions: Quit, Command Palette,
  Toggle Theme, New Window, Toggle Sidebar, and anything else
  whose lifetime is "the app is running."
- **View-level `.command(...)` (§4.2.2) — the scoped escape
  hatch.** The same modifier the previous section described, now
  positioned as the right choice only when a command's lifetime
  is genuinely tied to whether a specific view is rendered:
  sheet-local confirm/cancel, panel-local actions inside a
  `ChromeScope`, focus-conditional overrides, mode-specific
  commands.

The distinguishing rule is one sentence: **if a command's lifetime
is tied to whether a specific view is rendered, use
`.command(...)`; otherwise, hoist it to `.commands { }`.** Under
this design, the gallery's examples and the documentation's
defaults push authors to the scene-level slot first, so
accidental conditional hiding becomes an act the author had to
*consciously opt into* rather than a footgun lurking at every call
site.

#### 4.2.1 Scene-level `.commands { ... }` (primary)

```swift
extension Scene {
  /// Declares commands that are registered for the lifetime of
  /// this scene, independent of which views are currently
  /// rendered. Scene-level commands are the primary registration
  /// site for always-on actions; reach for this first and only
  /// step down to view-level ``View/command(id:title:key:…)`` when
  /// a command's lifetime is genuinely tied to a specific view's
  /// presence in the tree.
  ///
  /// Commands declared here flow into the same
  /// ``CommandPreferenceKey`` and ``HotkeyRegistry`` that
  /// view-level ``View/command(id:title:key:…)`` writes into, so
  /// every lens in this proposal (Help strip, Help sheet, Command
  /// palette, command-bound Toolbar items) picks them up without
  /// distinguishing their source.
  public func commands(
    @CommandsBuilder _ content: () -> [CommandItem]
  ) -> some Scene
}

/// A declarative command record used inside ``Scene/commands(_:)``.
/// Carries the same semantic fields as ``Command`` plus an action
/// closure that runs when the command is activated.
public struct CommandItem: Sendable {
  public init(
    id: String,
    title: String,
    key: KeyPress? = nil,
    group: String? = nil,
    detail: String? = nil,
    keywords: [String] = [],
    kind: Command.Kind = .action,
    isDisabled: Bool = false,
    action: @escaping @MainActor @Sendable () -> Void
  )
}

@resultBuilder
public enum CommandsBuilder {
  public static func buildBlock(_ components: CommandItem...) -> [CommandItem]
  public static func buildOptional(_ component: [CommandItem]?) -> [CommandItem]
  public static func buildEither(first: [CommandItem]) -> [CommandItem]
  public static func buildEither(second: [CommandItem]) -> [CommandItem]
  public static func buildLimitedAvailability(_ component: [CommandItem]) -> [CommandItem]
}
```

The `.commands { … }` modifier is declared on `Scene`, not on
`View`. This is a hard boundary: scene-level and view-level
registration are *different authoring sites with different
lifetimes*, and collapsing them into one modifier would
re-introduce the exact footgun this design is avoiding. The only
way to get scene-lifetime commands is to use the scene-level slot.

**State closure**: action closures declared inside `.commands { }`
capture the enclosing `App` type's state the same way `WindowGroup
{ ContentView() }` captures app-level state inside its content
builder. This is correct-by-construction for always-on commands:
they almost always operate on app-level state (quit, show palette,
switch theme, new window, toggle sidebar) rather than view-level
state. For commands that need view-level state, `.command(...)` on
the owning view is the right tier.

**Conditional commands are still expressible**, but at the
*scene-body* granularity rather than the view-body granularity:

```swift
var body: some Scene {
  WindowGroup {
    ContentView()
  }
  .commands {
    CommandItem(id: "quit", title: "Quit", key: .ctrl("q")) { quit() }

    // `buildOptional` lets you predicate on app-level state.
    if appModel.isAuthenticated {
      CommandItem(id: "sync", title: "Sync", key: .ctrl("r")) { sync() }
    }
  }
}
```

The `if` predicate here re-evaluates on scene body invalidation,
which is a much higher-level trigger than view body invalidation:
it fires when app-level state changes, not when an intermediate
view decides to hide itself. So the "command visible only while
signed in" case is still expressible and still correct, but it's
opted into deliberately at the scene level, not accidentally at
the view level.

**Implementation seam**: the `.commands { … }` modifier produces a
modified scene whose configuration carries a
`sceneCommands: [CommandItem]` field. At scene mount, the runtime
injects a root-level invisible view that applies a `.command(...)`
modifier for each `CommandItem` — i.e., scene-level commands reuse
the exact same registration path as view-level commands, just
attached to a view whose lifetime is "the scene is mounted." No
new registry, no new preference key, no new lifecycle hook. The
difference is *where* the author writes the declaration, not how
the runtime stores it.

**Help strip and palette behavior**: scene-level commands are
always part of the help strip and command palette, regardless of
which views are focused. View-level commands, as before, are
scoped to the focused subtree and override scene-level commands
with the same id (innermost wins). The "focus-conditional
override" pattern in §5.3 demonstrates this clearly.

> **Landing note:** the landed implementation introduces a primitive
> `CommandsModifiedScene<Base>` whose `traverseWindowScenes(...)`
> walks any nested `.commands { … }` layers, accumulates the items in
> source-reading order, and stashes them into a `TaskLocal` carrier
> (`SceneCommandItemsStorage.current`) for the duration of the inner
> scene's traversal. The innermost `WindowGroup` reads that carrier
> when constructing its window-scene configuration and wraps the
> root view in a `SceneCommandsInjection` `ResolvableView`, which
> publishes the items to both `CommandPreferenceKey` (so ancestors
> reading post-resolution see them) and a forward
> `\.sceneCommandRegistrations` environment channel (so descendant
> `.help()` / `.helpSheet()` modifiers see them during their own
> resolve pass, since preferences only flow bottom-up). No new visit
> signature, no new lifecycle hook — the existing scene visitors and
> the existing view-level command registration path are reused.

#### 4.2.2 View-level `.command(...)` (scoped escape hatch)

The view-level modifier is the existing API, extended to carry the
new `key` and `group` fields. It is positioned as the right choice
only when a command's lifetime is genuinely tied to a specific
view being in the tree:

- **Sheet/alert-local commands**: confirm / cancel / destructive
  actions that should only dispatch while the modal is open
  (§5.4).
- **Panel-local commands** inside a `ChromeScope` (§5.5): the
  files panel's Stage/Unstage, the commits panel's
  Checkout/Rebase — commands that are meaningful only when the
  panel is in the tree.
- **Focus-conditional overrides**: a detail screen that replaces
  the scene-level Quit with Close Document while focused
  (§5.3). The innermost-wins semantics of the preference
  reduction handle this exactly the way the previous draft
  described.
- **Mode-specific commands**: commands that only exist in certain
  modes (text edit mode's Accept/Reject, a game's pause-menu
  actions, a terminal multiplexer's copy-mode keys).

The API:

```swift
extension View {
  /// Registers a command scoped to this view's presence in the
  /// tree. Use this when a command's lifetime is genuinely tied to
  /// whether a specific view is rendered; otherwise prefer
  /// scene-level ``Scene/commands(_:)``.
  ///
  /// When `key:` is supplied, the modifier *also* registers a
  /// focus-independent hotkey binding so the keypress dispatches
  /// to `action` regardless of which view is focused (within the
  /// command's scope). The same declaration surfaces in:
  ///   - the command palette (existing behavior),
  ///   - any active `.help(...)` strip or sheet,
  ///   - any `ToolbarItem(command: id)` that names this command.
  public func command(
    id: String,
    title: String,
    key: KeyPress? = nil,
    group: String? = nil,
    detail: String? = nil,
    keywords: [String] = [],
    kind: Command.Kind = .action,
    isDisabled: Bool = false,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View
}
```

The modifier writes one record into the existing
`CommandPreferenceKey`. When `key` is present, it also calls
`hotkeyRegistry?.register(...)` with a binding whose `commandID`,
`label`, and `group` are populated from the command — exactly the
fields `HotkeyBinding` has had reserved space for since it was
written.

The lifecycle is automatic: when the subtree unmounts, the
existing `HotkeyRegistry.removeSubtrees(rootedAt:)` path tears the
binding down, and the preference reduction stops including the
command. The help strip and the palette both recompose without
needing to know anything about lifecycle. Scene-level commands use
this same lifecycle path; the only difference is that their owning
subtree is rooted at the scene, so unmount happens only when the
scene itself unmounts.

**Debug-mode flickering detection**: the runtime can optionally
warn when a view-level command registers and unregisters within a
small frame window (default 2 frames) because that is almost
always the footgun pattern — a command behind a conditional that
was supposed to be always-on flashing through during a
re-evaluation. See §10 open question 10 for the heuristic
details. The warning targets the pattern, not the API, so it
surfaces the problem whether the author used `.command(...)`
directly or through some higher-level abstraction.

**Migration of existing `.onKeyPress(...)` call sites**: the
`.onKeyPress(...)` modifier remains for low-level raw key
handling (text input, key trapping, mode-specific keys that
intentionally have no help discoverability). Authors who want
their keys to participate in the help system migrate them to
`.command(..., key: …)` at whichever tier is appropriate. This
is a *gradual* migration; both modifiers continue to work and
both write into `HotkeyRegistry`.

### 4.3 Lens 1: the Toolbar API

The toolbar is the **explicit author-placement** lens. It is
SwiftUI-faithful: items wrap real `View` content, the result builder
matches SwiftUI's, the placement cases are pruned but otherwise
unchanged.

**Critically**: `ToolbarItem` does **not** carry a `key:` parameter
and does **not** auto-register hotkeys. Registration is the
`.command(...)` modifier's job. A toolbar item may *refer to* a
command by id, in which case it pulls the command's title, key
glyph, and disabled state — but it doesn't create the command.

```swift
extension View {
  public func toolbar<Content: ToolbarContent>(
    @ToolbarContentBuilder content: () -> Content
  ) -> some View

  public func toolbar(
    _ visibility: Visibility,
    for bars: ToolbarPlacement...
  ) -> some View

  public func toolbarBackground<S: ShapeStyle>(
    _ style: S,
    for bars: ToolbarPlacement...
  ) -> some View
}

@MainActor
public protocol ToolbarContent {
  associatedtype Body: ToolbarContent
  @ToolbarContentBuilder var body: Body { get }
}
extension Never: ToolbarContent { /* primitive base */ }

@resultBuilder
public enum ToolbarContentBuilder {
  // buildBlock variadic, buildIf, buildEither, buildLimitedAvailability
}

public struct ToolbarItem<Content: View>: ToolbarContent {
  public typealias Body = Never

  /// Free-form item: a real View body in the explicit author-placed
  /// position. No command association, no key glyph rendering.
  public init(
    placement: ToolbarItemPlacement = .automatic,
    @ViewBuilder content: () -> Content
  )

  /// Command-bound item: pulls title, optional key glyph, and the
  /// disabled state from the command registered with `id`. The
  /// `Content` body is rendered *next to* the auto-rendered glyph,
  /// for cases where the author wants a richer label than the
  /// command's title alone.
  public init(
    placement: ToolbarItemPlacement = .automatic,
    command id: String,
    @ViewBuilder content: () -> Content
  )

  /// Command-bound item with the command's title as the body.
  public init(
    placement: ToolbarItemPlacement = .automatic,
    command id: String
  ) where Content == Text
}

public struct ToolbarItemGroup<Content: ToolbarContent>: ToolbarContent {
  public typealias Body = Never
  public init(
    placement: ToolbarItemPlacement = .automatic,
    @ToolbarContentBuilder content: () -> Content
  )
}

public struct ToolbarSpacer: ToolbarContent {
  public typealias Body = Never
  public enum Sizing: Sendable { case flexible, fixed(Int) }
  public init(
    _ sizing: Sizing = .flexible,
    placement: ToolbarItemPlacement = .automatic
  )
}

public enum ToolbarItemPlacement: Hashable, Sendable {
  case automatic            // resolves to .bottomBar in the default host
  case primaryAction        // dominant action; right-docked
  case secondaryAction      // less prominent; left/center
  case status               // status indicators (filename, dirtiness, progress)
  case bottomBar            // explicit bottom-row pinning
  case confirmationAction   // modal contexts only
  case cancellationAction   // modal contexts only
  case destructiveAction    // modal contexts only
  case title                // top title-row slot (no-op until title row ships)
}

public enum ToolbarPlacement: Hashable, Sendable {
  case automatic
  case bottomBar
  case statusBar
  case titleBar
}
```

**What the toolbar does not do** under this corrected design:

- It does not register hotkeys. (`.command(..., key: …)` does that.)
- It does not auto-derive items from the command registry. (Authors
  place items explicitly; the help system auto-derives.)
- It does not render F-key footers automatically. (The help strip
  does that, in the same row, alongside the toolbar items.)

**What the toolbar does do**:

- Lets the author place rich `View` content (status badges, inline
  progress, mode indicators) at semantic placements.
- Lets the author surface specific commands by id, in which case
  the command's title and key glyph render automatically as a
  derived label — but only because the *command* declares them, not
  because the toolbar item does.

This puts the toolbar firmly on the SwiftUI side of the divide. The
only divergence from SwiftUI is the pruned placement set
(§4.6 below), which is enforced by what chrome the framework
actually renders.

> **Landing note:** `.toolbar(_:for:)` and `.toolbarBackground(_:for:)`
> are **capture-only** in v1. Both modifiers ship with their declared
> signatures and write the authored `Visibility` /
> `AnyShapeStyle` records into package-internal preference channels
> (`ToolbarVisibilityPreferenceKey` and
> `ToolbarBackgroundPreferenceKey`), but the default toolbar host
> does not yet *consume* those channels at render time. The intent
> is to land the consumer in a follow-up once the host grows a
> per-bar visibility / background pass; until then, authors can
> declare the intent against the public surface today and the
> compiler will keep the call site stable. The capture-only caveat
> is documented on each modifier's docstring.

### 4.4 Lens 2: the Help system

The help system is the **auto-derived discoverability** lens. It
reads the active commands in the focused subtree (from the same
`CommandPreferenceKey` the palette already reads) and renders them
in two complementary forms:

- a **condensed help strip** — inline, single-row by default,
  truncates / scrolls / wraps on overflow
- an **expanded help sheet** — modal, multi-row, grouped by
  `Command.group`, triggered by `?` (or any key the author chooses)

Both forms read from the same data and stay in sync automatically.

```swift
extension View {
  /// Attaches an auto-derived help strip to the named bar(s) on
  /// this subtree. The strip pulls `Command` records from the
  /// focused subtree's command preference value, dedupes by
  /// `Command.id`, dims disabled commands in place, and renders
  /// each as a `[key] title` token with the key glyph drawn from
  /// `Command.key`.
  ///
  /// Commands whose `key` is `nil` are not shown in the strip
  /// (there is no glyph to render); they are still searchable in
  /// the command palette.
  ///
  /// The strip recomposes when focus moves within the subtree, the
  /// same way Textual's `Footer` recomposes on
  /// `screen.active_bindings`.
  public func help(
    _ style: HelpStripStyle = .bottomBar,
    overflow: HelpStripOverflow = .truncate
  ) -> some View

  /// Attaches an expandable help sheet to this subtree, presented
  /// when the user presses `key`. The sheet groups commands by
  /// `Command.group`, with one section per non-nil group plus a
  /// trailing "Other" section for commands without a group.
  ///
  /// Default trigger is `?`. The sheet is dismissible with
  /// `escape`.
  public func helpSheet(
    triggeredBy key: KeyPress = KeyPress(.character("?"))
  ) -> some View

  /// Combined convenience: attach both an inline help strip and an
  /// expandable help sheet with default settings.
  public func help() -> some View
}

public enum HelpStripStyle: Hashable, Sendable {
  /// Bottom-row inline strip. The default.
  case bottomBar

  /// Inline above the next sibling, useful for panel-local strips.
  case inline

  /// Bottom-row strip that hides itself once the user has dismissed
  /// it (and shows again on focus change).
  case dismissible
}

public enum HelpStripOverflow: Hashable, Sendable {
  case truncate                         // ellipsis (Charm bubbles/help)
  case scroll                           // horizontal scroll (Textual Footer)
  case wrap(maxRows: Int = 2)           // multi-row grid (k9s Menu)
}
```

The help strip is rendered at the same `ToolbarHost` row(s) the
toolbar uses. When both `.toolbar { … }` and `.help(...)` are
present on a host, the host composes them in one row: toolbar's
`.status` items on the left, help strip in the middle (filling
flexibly), toolbar's `.primaryAction` items right-docked.

The **help sheet** reuses the existing sheet presentation
infrastructure (`Sources/View/Presentation/PresentationModifiers.swift`,
`PresentationCoordinator.swift`) and renders a `VStack` of `Section`s,
one per `Command.group`, with each row showing the key glyph, title,
detail, and (if disabled) a dim treatment. It is essentially the
existing `CommandPalette` view minus the search field and plus
section headers — the same view types and the same data path.

Click-on-affordance synthesizes the keypress for both forms:
clicking `[^S] Save` in the strip dispatches `KeyPress(.ctrl, "s")`
through `HotkeyRegistry.dispatch(_:)`, the same path as the keyboard
event. This reuses the `PointerRouteView` machinery.

> **Landing note:** v1 implements only `HelpStripStyle.bottomBar` and
> `HelpStripOverflow.truncate`. The other style cases (`.inline`,
> `.dismissible`) and overflow cases (`.scroll`, `.wrap(maxRows:)`)
> are accepted at the public API and silently fall back to the
> bottom-bar / truncate rendering so authors can declare intent today
> without blocking on the secondary renderers. These fallbacks are
> documented on the public enum cases. A combined `.help()` no-arg
> convenience that attaches both the strip and the sheet was *not*
> shipped — authors call `.help()` and `.helpSheet()` separately,
> which keeps the two surfaces independently configurable and matches
> how the gallery composes them.

> **Landing note:** an earlier prototype tried to attach the help
> strip via the existing decoration / overlay layout path (the same
> seam the `.border(...)` revamp uses for layout-aware borders). That
> path turned out to fight with the toolbar host's bottom-row
> composition because the help strip needs to *share* a row with
> toolbar items, not stack as an overlay on top of the content. The
> shipped implementation abandons the decoration shape and instead
> composes a `VStack { content; bottomRow }` at the outermost
> toolbar/help host (see §4.6 below), which lets the help strip and
> toolbar items live in the same row by construction.

### 4.5 Lens 3: the Command palette (existing, unchanged)

The existing `.commandPalette(isPresented:)` modifier
(`CommandPalette.swift:644-660`) requires no API changes. It already
reads the `CommandPreferenceKey` registrations and presents them in
a fuzzy-searchable sheet.

What it gains automatically from the data-model unification:

- **Key glyphs in palette rows.** When a command has `key`, the
  palette renders a small key affordance in the row, the same way
  the help strip does. Authors who want their command palette to
  display `[^S] Save` in the row no longer need a parallel
  PrototypeKeyBindingToken.
- **Group section headers.** When commands have `group`, the
  palette can section results by group (or fold into the existing
  flat list — a small render-side flag).

These are **enhancements**, not breaking changes. The palette's
existing public API is preserved; its visual output gets richer
because the data is richer.

### 4.6 Toolbar host composition

A `ToolbarHost` is a host view that owns one or more reserved rows
for toolbar items, the help strip, or both. By default, every
`WindowGroup` is an implicit `ToolbarHost`. Sheets and alerts are
also `ToolbarHost`s — items declared inside a sheet's content
render in the sheet's bottom row, not the window's. This matches
SwiftUI's behavior where modal toolbars are nested.

Authors who want an explicit host inside their content (a panel
that owns its own bar, like a lazygit pane) can use:

```swift
public struct ChromeScope<Content: View>: View {
  public init(@ViewBuilder content: () -> Content)
}
```

`ChromeScope` collects toolbar items, help strips, and command
palette registrations only from its own subtree and renders them in
its own reserved rows. Commands declared inside a `ChromeScope` are
*not* visible to the enclosing window's command palette unless they
are also declared at the window level — this matches the focus
isolation expected by panel-local UIs.

The host's reserved row layout, when both toolbar items and a help
strip are present:

```text
┌─────────────────────────────── status ──┬─── help strip ──┬── primary action ──┐
│ ●  document.txt   ProgressView "Saving" │ [^P] Palette • [^Q] Quit │ [^S] Save │
└─────────────────────────────────────────┴──────────────────────────┴───────────┘
```

When only the help strip is present, the strip fills the whole row.
When only toolbar items are present, the strip slot is empty and
the items distribute according to their placements. When neither is
present, the row is hidden and its inset returned to content.

> **Landing note:** the toolbar host is implicit at every
> `WindowGroup` root in v1, but `ChromeScope` was *not* shipped (see
> §9 — it was pencilled in as v1.1). Composition between
> `.toolbar { … }` and `.help(...)` on the same subtree is mediated
> by two seams the proposal did not name:
>
> 1. A package-internal preference channel pair —
>    `ToolbarItemsPreferenceKey` and `HelpStripRequestPreferenceKey` —
>    that lets either modifier publish its records innermost-first
>    while an outer composer reads the merged value before composing
>    the bottom row.
> 2. An `IsInsideToolbarHostKey` environment flag set to `true` on
>    the subtree beneath the outermost composer. Nested
>    `.toolbar { … }` and `.help(...)` modifiers check the flag: when
>    it is `false`, the modifier composes its own
>    `VStack { content; bottomRow }`; when it is `true`, the modifier
>    only contributes to the preference channels and returns its
>    content unchanged.
>
> Together, these let `.help()` and `.toolbar { }` compose
> symmetrically — whichever modifier is outermost owns the row, and
> the inner one transparently feeds it. The shared preference channel
> also carries view-level command registrations and scene-level
> command items into the bottom-row composer so it can render
> command-bound `ToolbarItem` records and the `[key] title` strip
> tokens out of the same merged data set.

### 4.7 Pruned `ToolbarItemPlacement`

The set is pruned to the cases that have a TUI-relevant
interpretation. Each dropped case is dropped because it refers to
chrome the framework does not render.

| Case | Resolved slot in the default host | SwiftUI parallel |
| --- | --- | --- |
| `.automatic` | `.bottomBar` | matches SwiftUI's "system picks" |
| `.primaryAction` | right-docked, bottom row | matches SwiftUI |
| `.secondaryAction` | left/center, bottom row | matches SwiftUI |
| `.status` | left side, bottom row (or its own status row) | matches SwiftUI `.status` |
| `.bottomBar` | bottom row, explicit | matches SwiftUI |
| `.confirmationAction` | sheet/alert confirm slot | matches SwiftUI |
| `.cancellationAction` | sheet/alert cancel slot | matches SwiftUI |
| `.destructiveAction` | sheet/alert destructive slot | matches SwiftUI |
| `.title` | top title row (no-op until title row ships) | renamed from SwiftUI's `.principal` |

**Dropped from SwiftUI**: `.principal` (renamed to `.title`),
`.navigation`, `.navigationBarLeading`, `.navigationBarTrailing`,
`.topBarLeading`, `.topBarTrailing`, `.bottomOrnament`, `.keyboard`,
`.accessoryBar(id:)`. Each refers to chrome the framework does not
render. Reintroducing any of them is a future addition.

### 4.8 What the runtime does not need to grow

This is the smallest implementation of the corrected design.

- **No new registry.** `HotkeyRegistry` already exists, already
  has `label`, `group`, `commandID` fields on its records, and
  already manages lifecycle on subtree unmount. The unified
  `.command(..., key: …)` modifier writes into it through the
  existing `register(identity:binding:handler:)` API.
- **No new preference key.** The existing `CommandPreferenceKey`
  is the unified source of truth. The palette already reads from
  it; the help system reads from it; the toolbar reads from it
  for `commandID:`-bound items.
- **No new layout primitive.** The decoration-layout path used
  by `.border` (`Sources/View/Modifiers/Preference.swift:111-148`)
  is the same one the toolbar host row will use.
- **No new pointer routing.** `PointerRouteView` already routes
  clicks on a non-focusable visual to a registered handler.

What the runtime *does* need to grow:

- A `ToolbarHostNode` that reads the unified preference value and
  emits a `ResolvedNode` with `.decoration` layout behavior and a
  fixed height equal to the active row count.
- A small render component for the key glyph affordance, used by
  the help strip, the help sheet, and `commandID:`-bound toolbar
  items. The existing `PrototypeKeyBindingToken` is the prototype
  for this; it gets promoted into a public `KeyGlyphView`.
- A `Command` extension that adds `key` and `group` (one struct
  field addition each, plus updated initializers).
- A package-internal helper that turns a `Command` into a
  `HotkeyBinding` for registration and back into a `Command` for
  rendering — the bridge that lets `HotkeyBinding` remain the
  registry's record shape without leaking into the public surface.

## 5. Worked examples

The same screens authored under the unified design, exercising all
three lenses.

### 5.1 The minimum case — scene-level by default

```swift
@main
struct EditorApp: App {
  @State private var document = Document()

  var body: some Scene {
    WindowGroup {
      EditorScreen(document: $document)
    }
    .commands {
      CommandItem(id: "save", title: "Save",
                  key: .ctrl("s"), group: "Document") {
        document.save()
      }
      CommandItem(id: "quit", title: "Quit",
                  key: .ctrl("q"), group: "Session") {
        quit()
      }
    }
  }
}

struct EditorScreen: View {
  @Binding var document: Document

  var body: some View {
    TextEditor(text: $document.text)
      .help()
  }
}
```

The two commands are declared at the **scene** level, inside
`.commands { }`, so they are registered for the lifetime of the
scene regardless of which view EditorApp happens to be rendering.
The screen itself declares only `.help()` to light up the
auto-derived strip; it contains **zero** view-level
`.command(...)` calls, because neither Save nor Quit has a
lifetime that depends on a specific view being in the tree.

This is the "inverted default" in action. The simplest correct
authoring of this case has zero view-level commands. The bottom
row renders:

```text
[^S] Save • [^Q] Quit
```

Pressing `?` opens a sheet:

```text
┌─ Help ─────────────────────────────┐
│ Document                           │
│   [^S] Save                        │
│ Session                            │
│   [^Q] Quit                        │
└────────────────────────────────────┘
```

No toolbar declaration is needed for this case. The help system
handles it entirely. And because the commands are declared at the
scene level, there is nowhere in the view hierarchy an author
could have accidentally tucked them behind an `if`.

### 5.2 Status indicators + author-placed primary action

```swift
struct EditorScreen: View {
  @State private var document = Document()
  @State private var showPalette = false

  var body: some View {
    TextEditor(text: $document.text)
      .command(id: "save",      title: "Save",            key: .ctrl("s"), group: "Document") { document.save() }
      .command(id: "quit",      title: "Quit",            key: .ctrl("q"), group: "Session")  { quit() }
      .command(id: "palette",   title: "Command Palette", key: .ctrl("p"), group: "Session")  { showPalette = true }
      .toolbar {
        // Author-placed status views: rich `View` content the help
        // system cannot derive.
        ToolbarItem(placement: .status) {
          HStack(spacing: 1) {
            if document.isDirty {
              Text("●").foregroundStyle(.warning)
            }
            Text(document.path.lastPathComponent)
          }
        }
        // Right-docked, command-bound: the body is the command's
        // title rendered with its key glyph, pulled automatically
        // from the registry.
        ToolbarItem(placement: .primaryAction, command: "save")
      }
      .help()
      .commandPalette(isPresented: $showPalette)
  }
}
```

The bottom row composes the toolbar's status slot, the help strip
in the middle, and the toolbar's primary action right-docked:

```text
● document.txt    [^S] Save • [^Q] Quit • [^P] Command Palette         [^S] Save
```

The `[^S] Save` appears twice — once in the help strip (because
it's a registered command) and once in the right-docked toolbar
slot (because the author *also* placed it there for visual
prominence). Authors who want only the right-docked version can
suppress strip entries for specific commands with a `.helpHidden`
flag on the command (a small follow-up).

### 5.3 Two-tier split with a focus-conditional override

```swift
@main
struct AppShell: App {
  @State private var showingPalette = false

  var body: some Scene {
    WindowGroup {
      SplitLayout {
        Sidebar()
        DetailScreen()
      }
      .help()
      .commandPalette(isPresented: $showingPalette)
    }
    .commands {
      // Tier 1 — scene-level: always on, for the scene's lifetime.
      // These are the right tier because their lifetimes don't
      // depend on any specific view being rendered.
      CommandItem(id: "palette", title: "Palette",
                  key: .ctrl("p"), group: "Session") {
        showingPalette = true
      }
      CommandItem(id: "quit", title: "Quit",
                  key: .ctrl("q"), group: "Session") {
        quit()
      }
    }
  }
}

struct DetailScreen: View {
  var body: some View {
    EditorView()
      // Tier 2 — view-level: Save is meaningful only when a detail
      // screen is in the tree, so it's scoped to this view. When
      // the sidebar takes focus instead, Save unmounts and
      // disappears from the help strip.
      .command(id: "save", title: "Save",
               key: .ctrl("s"), group: "Document") {
        save()
      }
      // Tier 2 — focus-conditional override: replaces the
      // scene-level "Quit" command while this screen is focused,
      // because the same id appears deeper in the focused subtree.
      // Innermost wins. The override unmounts with the view, at
      // which point the scene-level "Quit" re-emerges.
      .command(id: "quit", title: "Close Document",
               key: .ctrl("q"), group: "Document",
               kind: .destructive) {
        closeDocument()
      }
  }
}
```

When focus is on the detail screen the help strip reads
`[^P] Palette • [^Q] Close Document • [^S] Save` and the help
sheet's "Document" section contains both Save and Close Document.
When the sidebar takes focus, the detail screen unmounts, the
override along with it, and the strip reverts to `[^P] Palette •
[^Q] Quit`. **Three surfaces — strip, sheet, palette — recompose
together** because they all read from the same preference key,
and the two tiers compose through the same innermost-wins
reduction.

The explicit split is the important part: an author reading this
code immediately sees which commands are app-lifetime (scene
slot) and which are view-lifetime (view modifier). There is no
ambiguity about where Save or Palette "lives."

### 5.4 Modal context

```swift
.sheet(isPresented: $showingExport) {
  ExportOptionsForm()
    .command(id: "cancel",  title: "Cancel", key: .escape, group: "Sheet") {
      showingExport = false
    }
    .command(id: "confirm", title: "Export", key: .return, group: "Sheet") {
      performExport()
      showingExport = false
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction, command: "cancel")
      ToolbarItem(placement: .confirmationAction, command: "confirm")
    }
    .help(.bottomBar)
}
```

Inside a sheet, the toolbar items route to the sheet's confirm/
cancel slots. The help strip renders inline at the sheet's bottom.
The window's bottom row is unaffected because the sheet is its own
toolbar host.

### 5.5 Panel-local scope

```swift
struct LazygitLikeShell: View {
  var body: some View {
    HSplit {
      ChromeScope {
        FilesPanel()
          .command(id: "stage",   title: "Stage",   key: .character("s"), group: "Files") { stage() }
          .command(id: "unstage", title: "Unstage", key: .character("u"), group: "Files") { unstage() }
          .help(.inline)
      }
      ChromeScope {
        CommitsPanel()
          .command(id: "checkout", title: "Checkout", key: .character("c"), group: "Commits") { … }
          .command(id: "rebase",   title: "Rebase",   key: .character("r"), group: "Commits") { … }
          .help(.inline)
      }
    }
  }
}
```

Each panel has its own help strip showing its own commands. Each
panel's commands are scoped to the `ChromeScope` and don't leak to
the other panel or to the app-wide command palette. This matches
the lazygit per-pane hint pattern surveyed in §3.4.

### 5.6 The cheatsheet-only style (helix-like)

```swift
ContentView()
  .command(id: "save",   title: "Save",   key: .ctrl("s"), group: "Document") { save() }
  .command(id: "quit",   title: "Quit",   key: .ctrl("q"), group: "Session")  { quit() }
  .helpSheet(triggeredBy: KeyPress(.character(" ")))   // space-mode menu
```

No `.help()` strip — the bottom row is left to other content. The
space key opens the expanded sheet. This is the helix / which-key
pattern.

## 6. Deviations from SwiftUI

The framework's deviation rule (`docs/VISION.md:39-50`) requires
(1) a well-considered justification, (2) a real terminal problem,
(3) explicit documentation. This proposal introduces **one
substantive deviation**, plus the established TUI placement-set
pruning.

**Deviation 1: a Help system as a peer of the toolbar.**

- *Problem*: SwiftUI has no help system because desktop GUIs
  surface key shortcuts in the menu bar. TUIs have no menu bar.
  The dominant TUI pattern (Textual's `Footer`, Charm's
  `bubbles/help`, htop's F-key footer, helix's space-mode) is to
  surface registered shortcuts as a visible affordance attached to
  the screen. Without a help system, TUI authors must hand-curate
  parallel label lists alongside their handlers — the exact
  footgun `PrototypeHelpSurface` makes vivid today.
- *Reinterpretation*: introduce `.help(...)` and `.helpSheet(...)`
  as auto-derived presentation lenses that read from the same
  command preference key the palette already reads. SwiftUI has no
  analogue; the divergence is justified by the absence of a TUI
  menu bar.

**Non-deviation (corrected from the previous draft): the toolbar is
SwiftUI-faithful.**

- The previous draft proposed `ToolbarItem(key: …, action: …)` so
  the toolbar would auto-register hotkeys and auto-render the key
  glyph. That was a conflation of two distinct concerns: explicit
  author placement and binding-derived discoverability. SwiftUI's
  toolbar does the first, not the second; SwiftUI relies on the
  menu bar (which the TUI doesn't have) for the second.
- The corrected design separates them. `.command(..., key: …)` is
  the registration site. `.help(...)` is the auto-derived
  discoverability surface. `ToolbarItem` is the author-placed
  surface. Each surface has one job. The toolbar matches SwiftUI
  exactly on the parts it covers.

**Deviations *avoided* (kept consistent with SwiftUI even though
the TUI could justify a divergence)**:

- The result-builder shape, the `ToolbarContent` associatedtype
  model, the `ToolbarItem` / `ToolbarItemGroup` / `ToolbarSpacer`
  primitives, and the two-namespace split between item placement
  and bar visibility are all preserved unchanged.
- `.commandPalette(isPresented:)` is preserved unchanged — this is
  not a SwiftUI API, but it is *this repo's* established command
  surface, and a holistic redesign that retconned it would do more
  harm than good.
- `Scene.commands { … }` mirrors SwiftUI's `App.commands { … }`
  slot in intent (an always-evaluated command registration site
  whose lifetime is a scene/app), but differs in two concrete
  ways: (a) TerminalUI declares the slot on `Scene` rather than
  on `App` because TerminalUI apps can have multiple scenes with
  different command sets, and (b) the builder produces a
  `[CommandItem]` list rather than `CommandMenu` / `CommandGroup`
  primitives, because TUI apps have no menu bar to organize
  commands into. The *intent* of giving authors a non-body
  registration site matches SwiftUI exactly; the primitives
  differ because the physical surface differs.

**Deliberately deferred architectural decisions**:

- **`NavigationStack` is not introduced by this proposal.** The
  previous question "should TerminalUI introduce a navigation
  stack to give commands a natural non-body registration site?"
  was considered and rejected in §4.2. Reasons: VISION.md defers
  `NavigationStack` for unrelated reasons; the feature is a much
  larger API whose primary value propositions are orthogonal to
  command scope; TUI apps are more often panel-shaped than
  stack-shaped; and even with `NavigationStack` the same
  flickering-conditional footgun still exists inside any single
  screen. The two-tier `.commands { }` + `.command(...)` split
  solves the footgun with a much smaller API, and
  `NavigationStack` can still land later on its own merits
  without disturbing this design.

## 7. Implementation notes

What this proposal *does not require* the runtime to grow:

- **No new registry.** The unified `Command` reuses the existing
  `CommandPreferenceKey`. The unified `.command(..., key: …)`
  modifier reuses the existing `HotkeyRegistry.register(...)` API.
  The bridge between `Command` and `HotkeyBinding` is a small
  package-internal helper, not a new subsystem.
- **No new layout primitive.** The decoration-layout path used by
  `.border` is the same one the host row uses. Reserved frame
  insets, not content overdraw.
- **No new preference flavor.** `CommandPreferenceKey` is the one
  source of truth. The toolbar's `commandID:`-bound items resolve
  by looking up the id in the focused subtree's reduction.
- **No new pointer routing.** `PointerRouteView` already routes
  clicks on non-focusable visuals to handlers. Help-strip key
  affordances and toolbar item affordances both reuse it.

What the runtime *does* need:

- **`Command` field additions**: `key: KeyPress?`, `group: String?`.
  Existing initializers default both to `nil`; existing call sites
  continue to compile.
- **A small `Command ↔ HotkeyBinding` bridge** (package-internal):
  one function each direction. `HotkeyBinding` can be deleted from
  the public namespace entirely; it is already package-internal.
- **Scene-level command injection**: `Scene.commands { … }` needs a
  new `WindowSceneConfiguration` field (or equivalent) carrying a
  `[CommandItem]` list. At scene mount, the runtime attaches an
  invisible root view that applies `.command(...)` for each
  `CommandItem`, so scene-level commands reuse the exact same
  registration and lifecycle path as view-level commands. The
  scene-level modifier is pure sugar over the view-level one;
  there is no second code path.
- **A `CommandItem` value type**: `Sendable`, carrying the same
  semantic fields as `Command` plus the `@MainActor @Sendable`
  action closure. Parallel to the existing internal
  `CommandRegistration` struct (`CommandPalette.swift:209-231`),
  promoted to public API for the `.commands { }` builder.
- **A `ToolbarHostNode`** that reads the unified preference value,
  resolves `.automatic` placements per host, sorts by `(toolbar
  status / help strip / toolbar primary)` lanes, and emits a
  `ResolvedNode` with `.decoration` layout behavior.
- **A public `KeyGlyphView`** promoted from
  `PrototypeKeyBindingToken`. Used by the help strip, the help
  sheet, the command palette rows, and `commandID:`-bound toolbar
  items. One renderer for all four surfaces.
- **A `HelpStripView`** that consumes a deduped `[Command]` and
  applies the `HelpStripOverflow` strategy. Internally a thin
  wrapper around `HStack` + `ScrollView` + the existing layout
  primitives — no new layout work.
- **A `HelpSheetView`** that consumes a deduped `[Command]`,
  groups by `Command.group`, and renders sections through the
  existing sheet presentation infrastructure.

The bulk of the work is the public surface and the
section/dedup/scope policy, not new infrastructure. The runtime
already does the hard parts.

## 8. Testing strategy

The proposal touches three surfaces that already have testing
patterns to copy:

- **Command resolution and dedup**: `Tests/CoreTests` snapshot
  tests on the reduced `CommandPreferenceKey` value — verify
  innermost-wins dedup is correct, that scope-bounded `ChromeScope`
  collects only its own subtree, and that disabled commands
  remain in the reduction (not filtered out at the data layer).
- **Hotkey lifecycle**: `Tests/TerminalUITests` exercising
  `HotkeyRegistry` after a `.command(..., key: …)` subtree is
  mounted/unmounted — verify the binding shows up, dispatches,
  and is removed on unmount. The same tests catch regressions in
  the `.onKeyPress` path because both write into the registry.
- **Help strip rendering**: snapshot tests of the rendered
  terminal output for each `HelpStripOverflow` strategy, plus
  recompose-on-focus-change tests using the existing focus test
  scaffolding.
- **Toolbar host layout**: snapshot tests verifying that content
  is not overdrawn by the bottom row even when the content extends
  to the bottom edge — the same regression guard the border revamp
  added.
- **Pointer routing**: extend the `PointerRouteView` test pattern
  used by the TabView tab-strip tests to a help-strip key
  affordance, verifying that a click synthesizes the right
  `KeyPress` and that the dispatch is observably equivalent to a
  keyboard event.
- **Cross-surface integration**: a small set of tests that declare
  a command and assert it shows up in *all four* surfaces — strip,
  sheet, palette, and a `commandID:`-bound toolbar item — within
  the same view tree. This is the test that catches the kind of
  drift the previous draft would have allowed.

No new test infrastructure is needed.

## 9. Migration plan

1. **Land the data-model unification first.** Add `key` and
   `group` fields to `Command`. Add the new `key:`/`group:`
   parameters to view-level `.command(...)`. Wire the modifier
   to register into `HotkeyRegistry` when `key` is non-nil. This
   is the smallest atomic change and unblocks everything else.
2. **Land the scene-level `.commands { … }` slot second.** Ship
   `CommandItem`, `CommandsBuilder`, and the `Scene.commands(_:)`
   modifier. The implementation injects `CommandItem` records at
   the scene root so they reuse the view-level registration path,
   which keeps the runtime seam small. Shipping this tier before
   the help system ensures that by the time the help strip can
   render, the correct authoring-site defaults are already
   available — gallery demos written against the help system can
   then model the inverted default from the start.
3. **Land the help system third.** Ship `.help(...)`,
   `.helpSheet(...)`, `HelpStripStyle`, `HelpStripOverflow`, the
   public `KeyGlyphView`, and the `ToolbarHostNode` wrapper that
   handles the bottom-row rendering. Update the gallery to use
   `.help()` instead of `PrototypeHelpSurface`, with commands
   hoisted to `.commands { }` wherever their lifetime is
   app-scoped.
4. **Land the toolbar surface fourth.** Ship `ToolbarContent`,
   `ToolbarContentBuilder`, `ToolbarItem`, `ToolbarItemGroup`,
   `ToolbarSpacer`, `ToolbarItemPlacement`, `ToolbarPlacement`,
   the `.toolbar { … }` modifier, and the implicit `WindowGroup`
   host. Update the gallery to use `.toolbar { … }` for status
   slots and primary actions.
5. **Land `ChromeScope` fifth** (optional in v1, can defer to
   v1.1).
6. **Delete `PrototypeUIComponents/PrototypeHelpSurface` and
   `PrototypeKeyBindingGroup`** once the gallery has fully moved
   over. This is the cleanup that proves the public surface
   subsumed the prototype.
7. **Update `docs/PUBLIC_API_INVENTORY.md`** with rows for the new
   surface, mirroring the shape/border revamp's entries.
   Specifically: `Scene.commands(_:)`, `CommandItem`,
   `CommandsBuilder`, the extended `Command` fields, the
   `.command(..., key:group:)` view modifier, `.help(...)`,
   `.helpSheet(...)`, `HelpStripStyle`, `HelpStripOverflow`,
   `ToolbarContent`, `ToolbarItem`, `ToolbarItemGroup`,
   `ToolbarSpacer`, `ToolbarItemPlacement`, `ToolbarPlacement`,
   `KeyGlyphView`.
8. **Update `docs/LIPGLOSS_SWIFTUI_EQUIVALENTS.md`** with rows
   for bubbles/key + bubbles/help and Textual `BINDINGS` →
   `Footer`. The Textual `App.BINDINGS` class-level declaration
   maps directly to `Scene.commands { … }`; per-screen
   `Screen.BINDINGS` maps to view-level `.command(...)`.
9. **Update `docs/STATUS.md`** to remove the "long-term home for
   prototype help-strip and launcher-like shell workflows" gap
   from the unsettled list.

A general `.keyboardShortcut(_:modifiers:)` modifier (for buttons
without commands), a `.title`-row host, and `ChromeScope` are all
explicit v1.1 follow-ups, gated on actual gallery demand.

## 10. Open questions

These are calls the proposal does not yet make and that should be
decided in review.

1. **Default trigger key for the help sheet.** `?` is the universal
   convention in TUIs but it conflicts with literal `?` text input.
   Should the default be `?` only when no text input is focused, or
   should it require a modifier (`Alt-?`, `F1`)?
2. **Should the help strip and the toolbar share a row by default?**
   The proposal lets them coexist in one row (status / strip /
   primary). A cleaner alternative is to give them separate rows
   when both are present. The "shared row" choice matches Textual
   and lazygit; the "separate rows" choice matches k9s. v1 can
   ship one and add a `.helpStripPlacement(.ownRow)` modifier
   later if needed.
3. **Should commands without a `key` show in the help strip?** v1
   says no (no glyph to render → strip omits them; sheet still
   includes them under their group). An alternative is to render
   them as `[—] Title` placeholders so the user knows the action
   exists but is keyless. The first option is cleaner; the second
   is more discoverable.
4. **`KeyPress` shorthand initializers.** `key: .ctrl("s")` is
   nice. The repo today uses `KeyPress(.character("s"), modifiers:
   .ctrl)`. Adding shorthand initializers on `KeyPress` is a small
   companion change; should it land in the same milestone?
5. **Multiple keys for the same action.** A command could grow
   `keys: [KeyPress]` so the same action registers under several
   bindings, with the help system rendering only the first. v1
   keeps the singular `key:`; the plural form is a follow-up if
   real apps demand it.
6. **`.helpHidden` on individual commands.** Authors who want a
   command in the palette but not in the strip (e.g. a destructive
   action behind a menu) need a flag. Smallest version is a
   `helpHidden: Bool = false` parameter on `.command(...)`. Worth
   shipping in v1 or defer?
7. **Sheet/alert host integration ordering.** The existing
   `PresentationCoordinator` does not yet expose a "this sheet is
   a toolbar host" hook. Adding that hook is part of the work,
   but the ordering matters: should the unified Command surface
   land first (with sheet integration as a follow-up) or block on
   the presentation hook?
8. **`commandID:`-binding to a missing command.** What does
   `ToolbarItem(command: "nonexistent")` render? Empty? An error
   token? Silently omit? The third is most forgiving but masks
   typos. v1 should pick one; "silently omit + warn at debug" is
   the safest default.
9. **Should `ChromeScope` ship in v1?** Real apps need it
   eventually (lazygit-style per-pane chrome), but a minimal v1
   ships only the implicit `WindowGroup` host. Same call as the
   previous draft — defer to v1.1 unless a gallery demo
   genuinely needs it.
10. **Debug-mode flickering-command detection.** The runtime
    could emit a warning when a view-level `.command(...)`
    registers and then unregisters within a small frame window
    (default 2 frames) because that pattern almost always
    indicates a command that was supposed to be always-on but
    ended up behind a conditional. Open questions: what's the
    right frame-window threshold? Should intentional
    scope-dependent commands (sheet-local, panel-local) be able
    to suppress the warning with a `scopeHint: .transient` flag?
    Should the warning fire once per command id per session, or
    every time? Should it be enabled in debug builds by default
    or gated behind an env var?
11. **Can scene-level commands reference view-level state?**
    Strictly no — scene-level action closures capture the `App`
    type's stored properties, not any specific view's `@State`.
    Authors who need a command that operates on view-level state
    must register it at the view level (by design; this is the
    correct-by-construction rule of §4.2). Worth calling out in
    the docs so the error message when an author tries to capture
    view-local state explains the tier split, not just the
    closure capture rule.
12. **`CommandItem` vs. `Command` naming.** The v1 design uses a
    separate `CommandItem` type as the literal inside
    `.commands { }` because `Command` is Hashable/Sendable and
    adding an `action:` closure to it would break that. An
    alternative is to rename `Command` to `CommandDescriptor` and
    reserve `Command` as the action-bearing literal. The rename
    is cleaner long-term but has churn cost. Worth discussing.

## 11. Out of scope for this proposal

To keep the v1 surface focused, the following are explicit
non-goals — each is a reasonable future addition but does not need
to land with this story.

- **Customizable toolbars** with persistence, drag-to-rearrange,
  or hidden-by-default items. No analogous user affordance exists
  in the TUI.
- **`ToolbarRole`**, **`ToolbarTitleMenu`**, and
  **`.toolbarTitleDisplayMode`**. All presuppose chrome the
  framework does not render.
- **A general `.keyboardShortcut(_:modifiers:)` view modifier.**
  v1's keyboard story for commands is `.command(..., key: …)`;
  the general modifier (for buttons-without-commands) can land
  later without disturbing this design.
- **A header / breadcrumb bar.** `TabView` already provides the
  most TUI-relevant top-row chrome. A header bar can be added
  later by giving `WindowGroup` a `.title`-row policy.
- **Anchor-based item positioning.** STATUS.md flags
  `anchorPreference(...)` as deferred until local coordinate
  spaces ship (`docs/STATUS.md:74-75`); the toolbar layout does
  not need anchors.
- **Customizable key glyph rendering.** v1 ships a single style
  consistent with `PrototypeKeyBindingToken`. Theming the key
  glyphs is a follow-up.
- **A which-key style cascading menu** (helix space-mode prefix
  trees). The proposal's `.helpSheet(triggeredBy: KeyPress(...))`
  covers the simple "press one key, see all commands grouped"
  case but does not cover prefix-tree disclosure
  (`<space> w v` to split a window). That is a separate, larger
  surface and a v2 conversation.

## 12. Why this is worth shipping now

The vision document treats "terminal-native help and keybinding
surfaces" as a prototype-first item to land "once the
terminal-specific interaction model is clear and the API still
reads like the same product" (`docs/VISION.md:79-86`). The
conditions for that are met:

- The interaction model **is** clear: focus-driven scope,
  keyboard-first with pointer augmentation, a `HotkeyRegistry`
  already lifecycle-managed against subtree mount/unmount, and a
  `CommandPreferenceKey` already serving as the unified registry
  the palette reads from.
- The product **does** read like the same product: the proposed
  surface is `.command(..., key: …) { … }` plus
  `.toolbar { ToolbarItem(...) }` plus `.help()` — the same
  shapes an author already knows from SwiftUI, with one
  well-justified divergence (a help system as a peer of the
  toolbar) and a pruned placement set.
- The prototype **has run its course**: `PrototypeHelpSurface` /
  `PrototypeKeyBindingGroup` proved the rendering layout works
  and proved that hand-curated parallel lists are a footgun.
  Subsuming it into the public surface is the natural next step
  the way the border revamp subsumed the half-built
  `ShapeOperation` / `LineVariant` exploration in the previous
  milestone (`docs/proposals/SHAPE_AND_BORDER_APIS.md:67-167`).
- The data-model fragmentation **has a clear seam**: `Command`
  and `HotkeyBinding` are nearly-identical structs that today
  live in different files and don't know about each other. The
  unification is two field additions and one bridge function.
- The runtime cost is **bounded**: no new registry, no new
  layout primitive, no new pointer routing. The proposal is
  three public surfaces sitting on top of infrastructure that
  is already shipping and already tested.

The previous draft of this proposal was not wrong about the
*destination* — a fluent, focus-driven, scope-aware
discoverability story that doesn't force authors to maintain
parallel hand-curated lists. It was wrong about the *shape* of
that story. Separating "explicit author placement" from
"binding-derived discoverability" gives each surface a single
job, makes the toolbar SwiftUI-faithful, makes the help system a
proper first-class peer rather than a hidden behavior of an
overloaded toolbar item, and lets the existing command palette
participate without any API change at all. One model, three
lenses.
