# Toolbar Implementation Plan

**Date:** 2026-04-02
**Status:** Landed
**Scope:** replace the keyboard-help-specific API with a general toolbar and
contextual toolbar-item surface

## Goal

Replace the current keyboard-help API:

- `.keyboardShortcut(...)`
- `.keyboardShortcutHelp(...)`

with a more general terminal-native toolbar surface that can host both passive
information and active controls.

This plan is retained as the implementation record for the landed toolbar
surface and the removal of the old keyboard-help API.

The replacement should stay SwiftUI-shaped at the authoring layer, use the
existing resolve-time preference hoisting patterns already present in the
repository, and deliberately avoid backward-compatibility shims for the removed
keyboard-help API.

## Why This Change

The current `keyboardShortcut` surface conflates three separate concerns:

- global key dispatch
- human-readable keyboard help
- bottom-strip rendering

That coupling is too narrow for where the project is heading. The repository
already wants a broader terminal-native shell story, and toolbar-like chrome is
explicitly listed in [VISION.md](VISION.md) and [STATUS.md](STATUS.md) as a
deferred but expected surface.

This slice should therefore:

- graduate the help strip into a supported `View` API
- generalize it beyond keyboard shortcuts
- keep keyboard dispatch on the existing `onKeyPress` or control-action path
- establish the root-host and placement model we can reuse for future app-shell
  chrome

## Non-Goals

This plan does not attempt to support:

- any compatibility layer for `.keyboardShortcut(...)` or
  `.keyboardShortcutHelp(...)`
- automatic migration from old APIs
- multi-row or wrapping toolbars
- animated toolbar insertion or removal
- overflow menus, chevrons, or truncation affordances
- per-item placement beyond leading and trailing
- toolbar item placements such as principal, status, keyboard, or navigation
- a separate keyboard-command abstraction beyond the existing `.onKeyPress(...)`
  surface
- more than one shipped toolbar style in v1

## Public API

The public surface should stay intentionally small:

```swift
public enum ToolbarPlacement: Hashable, Sendable {
  case top
  case bottom
}

public enum ToolbarAlignment: Hashable, Sendable {
  case leading
  case trailing
}

public enum ToolbarStyle: Hashable, Sendable {
  case `default`
}

extension View {
  public func toolbar<Leading: View, Trailing: View>(
    placement: ToolbarPlacement = .bottom,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View

  public func toolbarItem<Item: View>(
    alignment: ToolbarAlignment,
    isEnabled: Bool = true,
    @ViewBuilder item: () -> Item
  ) -> some View

  public func toolbarStyle(
    _ style: ToolbarStyle
  ) -> some View
}
```

### API Notes

- `toolbar(placement:leading:trailing)` defines a toolbar for a placement.
- A toolbar is absent unless `.toolbar(...)` is explicitly authored.
- `toolbarItem(...)` does not create a toolbar by itself.
- `toolbarItem(...)` is intentionally generic content. It may contain `Button`,
  `Text`, `Label`, custom views, or any other ordinary `View`.
- `toolbarStyle(.default)` is the only shipped style in v1, but the style
  should still flow through environment storage so later additions do not
  require a structural redesign.

## Behavioral Semantics

### 1. Toolbar Presence And Consolidation

- There may be at most one rendered toolbar per placement (`.top` and
  `.bottom`).
- Multiple `.toolbar(placement: .bottom, ...)` declarations do not create
  stacked bottom bars. Their contents are consolidated into one bottom toolbar.
- The same rule applies independently to `.top`.
- Top and bottom toolbars may coexist at the same time.

### 2. Static Versus Contextual Content

- The `leading` and `trailing` builders passed to `.toolbar(...)` define the
  static outer edges of the toolbar.
- Those static items always render first from their side and are never dropped
  in favor of contextual `toolbarItem(...)` content.
- `toolbarItem(...)` contributes contextual content that renders inside the
  already-declared static items for the same alignment.
- “Inside” means closer to the toolbar center than the corresponding static
  leading or trailing content.

### 3. Ordering

- Static toolbar content is ordered by placement declaration depth, with
  shallower declarations closer to the outside edge and deeper declarations
  placed farther inward.
- Contextual `toolbarItem(...)` content is ordered the same way: shallower
  registrations stay closer to the edge, deeper registrations move farther
  toward the center.
- Ties at the same depth resolve in normal view-tree reduction order so the
  layout stays deterministic.

This preserves the requested stacking rule: deeper contextual items land farther
in toward the center.

### 4. Placement Scope For `toolbarItem(...)`

The proposed `toolbarItem(...)` API intentionally does not carry a placement,
which leaves one ambiguity when both top and bottom toolbars exist.

Assumption for v1:

- a contextual `toolbarItem(...)` targets the nearest ancestor toolbar scope
  established by `.toolbar(...)`
- if no toolbar scope exists above the item, the item is ignored

This keeps the requested signature intact and avoids silently duplicating the
same contextual item into both top and bottom bars. If the framework later
needs one subtree to target multiple placements explicitly, that should be a
new overload rather than hidden v1 behavior.

### 5. Enabled State

- `isEnabled` affects interaction and styling, not registration.
- Disabled toolbar items still participate in layout and overflow decisions.
- Disabled toolbar buttons should behave the same way other disabled controls in
  the repo behave today: visible, non-interactive, and styled through the
  existing enabled-state environment.

### 6. Overflow And Focus Selection

If all active contextual items fit, the toolbar shows them all.

If they do not fit, selection is focus-aware:

- static `toolbar(...)` items remain visible
- contextual candidates are ranked by closeness to the current focused identity
- the closest candidates win until there is no room for additional contextual
  content

Recommended closeness heuristic:

1. prefer registrations on the focused identity itself
2. then prefer registrations whose identity is an ancestor of the focused
   identity
3. then prefer registrations with the deepest shared ancestor with the focused
   identity
4. then prefer registrations with the fewest identity-path hops away
5. finally break ties by normal view-tree order

Important distinction:

- focus decides which contextual items survive overflow
- depth still decides where the surviving items render from the edge inward

If there is no focused identity, contextual overflow falls back to normal
declaration order.

### 7. Center Crossing And Clobbering

Toolbar items may extend past the visual midpoint if the opposite side is not
using that space.

When collision happens, home-side occupancy wins:

- a leading item that has crossed into the trailing half loses to trailing
  content that still occupies its own half
- a trailing item that has crossed into the leading half loses to leading
  content that still occupies its own half

This matches the requested rule:

- crossing the center is allowed
- but a crossing item is clobbered by an item that is still on its own side

The simplest implementation rule is:

- place each side from the outer edge inward
- treat each side’s home half as protected when the opposite side still has
  content there
- allow overflow beyond the midpoint only into otherwise-unused cells

### 8. Toolbar Height

v1 should be a single-row terminal surface.

Reasons:

- it is the direct replacement for the current one-line help strip
- it keeps the shell chrome consistent with terminal-native status-line
  patterns
- it avoids inventing a wrapping or multi-row toolbar model before the repo has
  broader app-shell semantics

Toolbar content should therefore be measured with a one-row expectation. Taller
authored content is out of scope for this slice.

## Styling

`toolbarStyle(.default)` should render restrained terminal-native chrome:

- full-width bar
- one-row height
- no ornamental gradients or decorative framing
- foreground and disabled styling inherited through the existing style
  environment
- background/chrome implemented with the same terminal-native styling system
  already used by presentation and control surfaces

Recommended default:

- use a subtle terminal surface or row treatment rather than a bordered panel
- keep spacing as the primary separator between items

## Core Design Decisions

### 1. Remove The Old API Instead Of Aliasing It

There should be no deprecated wrappers and no hidden compatibility behavior.

Implementation consequences:

- remove `KeyboardShortcut`
- remove `KeyboardShortcutGroup`
- remove `KeyboardShortcutHelpView`
- remove `.keyboardShortcut(...)`
- remove `.keyboardShortcutHelp(...)`
- remove the shortcut-help-specific tests and docs

### 2. Keep Keyboard Dispatch Separate From Toolbar Authoring

The toolbar API is a presentation surface, not a command system.

That means:

- toolbar items may display key hints, but they do not register hotkeys by
  themselves
- keyboard-triggered behavior should continue to use `.onKeyPress(...)` or the
  existing control-action path
- any current internal caller using `.keyboardShortcut(...)` for dispatch should
  be migrated to direct key handling plus explicit toolbar authoring where
  needed

The main current internal migration point is
[CommandPalette.swift](../Sources/View/Presentation/CommandPalette.swift),
which should stop routing its shortcut through the removed API.

### 3. Host Toolbars At The Root Chrome Layer

Toolbars should render as actual shell chrome, not subtree overlays.

Recommended structure:

- add a `ToolbarHostingRoot` in `View` presentation code
- wrap the authored root with it inside
  [TerminalUI.swift](../Sources/TerminalUI/TerminalUI.swift)
- keep the existing modal and toast hosts outside it so overlays still appear
  over the whole frame

Recommended render stack:

```swift
ToastHostingRoot(
  content: TerminalPresentationHostingRoot(
    content: ToolbarHostingRoot(content: root)
  )
)
```

This makes top and bottom bars reserve real rows instead of obscuring content.

### 4. Reuse The Existing Preference-Hoisting Pattern

The repository already uses resolve-time preferences for commands, sheets,
dialogs, and toasts. Toolbars should follow the same approach.

Recommended model:

- `.toolbar(...)` writes a toolbar-definition preference
- `.toolbarItem(...)` writes a contextual-toolbar-item preference
- `ToolbarHostingRoot` resolves the base tree, reads the merged preference
  state, and builds the top and bottom toolbar chrome around the content

Each registration should capture at least:

- attachment identity
- placement scope
- alignment
- enabled state
- declared child views
- authoring depth or equivalent identity depth

### 5. Use A Dedicated Toolbar Layout Instead Of Ad Hoc HStacks

The center-crossing and focus-aware overflow rules are too specific for a plain
`HStack { ... Spacer() ... }` composition.

Recommended shape:

- a small internal `Layout` implementation dedicated to toolbar rows
- measure each selected item under an unconstrained horizontal proposal and
  one-row vertical proposal
- place leading and trailing lanes manually from the edges inward
- apply the midpoint clobber rule during placement

This keeps the behavior explicit and testable without needing new pipeline
types in `Core`.

### 6. Use Identity-Path Closeness For Overflow Selection

The current runtime already treats identity paths and focus ownership as the
authoritative context model. That makes identity distance the right heuristic
for “closest wins.”

This is preferable to:

- plain declaration order, which ignores focus entirely
- geometry distance, which would require later-stage data the preference pass
  does not have
- control-type introspection, which would make the toolbar system too magical

## Implementation Plan

### Phase 1: Public API And Model Replacement

Primary files:

- [KeyboardShortcuts.swift](../Sources/View/Presentation/KeyboardShortcuts.swift)
- [StyleModifiers.swift](../Sources/View/Modifiers/StyleModifiers.swift)
- [StyleEnvironment.swift](../Sources/View/Environment/StyleEnvironment.swift)

Changes:

- delete the keyboard-help-specific public types and modifiers
- introduce `ToolbarPlacement`, `ToolbarAlignment`, and `ToolbarStyle`
- add `.toolbar(...)`, `.toolbarItem(...)`, and `.toolbarStyle(...)`
- add any needed environment key for the current toolbar style
- add any needed environment or scope marker used by `toolbarItem(...)` to bind
  to the nearest toolbar placement

Expected result:

- the public authoring surface is toolbar-first rather than shortcut-first
- there is no remaining supported API for keyboard help strips

### Phase 2: Root Hosting And Layout

Primary files:

- [TerminalUI.swift](../Sources/TerminalUI/TerminalUI.swift)
- new `Sources/View/Presentation/Toolbar.swift`
- optionally new `Sources/View/Presentation/ToolbarLayout.swift` if the layout
  logic becomes large enough to justify a split

Changes:

- add toolbar preference types and registration modifiers
- add `ToolbarHostingRoot`
- implement consolidated top and bottom toolbar surfaces
- implement the dedicated one-row layout and overflow selection logic
- reserve actual content rows for top and bottom bars

Expected result:

- toolbars render as shell chrome rather than overlays
- `.top` and `.bottom` toolbars can coexist
- overflow selection follows the focus heuristic and center-clobber rule

### Phase 3: Internal Surface Migration

Primary files:

- [CommandPalette.swift](../Sources/View/Presentation/CommandPalette.swift)

Changes:

- remove internal dependence on `.keyboardShortcut(...)`
- reimplement `commandPalette(shortcut:...)` with direct `.onKeyPress(...)`
  behavior or an equivalent direct hotkey registration path
- keep command-palette shortcut behavior working without reintroducing the
  removed API indirectly

Expected result:

- removing the old keyboard-help API does not regress command-palette shortcut
  activation

### Phase 4: Tests And Docs Cleanup

Primary files:

- replace `Tests/ViewTests/KeyboardShortcutParsingTests.swift` with a toolbar
  surface test file, preferably `Tests/ViewTests/ToolbarSurfaceTests.swift`
- [InteractiveRuntimeTests.swift](../Tests/TerminalUITests/InteractiveRuntimeTests.swift)
- new `Tests/TerminalUITests/ToolbarSurfaceTests.swift`
- [docs/README.md](README.md)
- [README.md](../README.md)
- [STATUS.md](STATUS.md)
- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md)

Changes:

- remove shortcut-help rendering tests
- add toolbar rendering, ordering, disabled-state, and overflow-selection tests
- add runtime tests that confirm command-palette shortcuts still dispatch
- replace docs that describe help strips as the relevant public direction
- move toolbar work out of the “deferred” bucket once it lands

## Verification

Recommended test coverage:

- `Tests/ViewTests/ToolbarSurfaceTests.swift`
  - toolbar is absent without `.toolbar(...)`
  - static leading and trailing content render in the correct edges
  - contextual `toolbarItem(...)` content renders inside static items
  - disabled toolbar items render but do not activate
  - multiple toolbar declarations at the same placement consolidate
- `Tests/TerminalUITests/ToolbarSurfaceTests.swift`
  - top and bottom bars reserve rows instead of overlaying content
  - focus-sensitive overflow prefers the closest contextual items
  - center crossing is allowed only into unused space
  - opposite-side home occupancy clobbers crossing content
- `Tests/TerminalUITests/InteractiveRuntimeTests.swift`
  - `commandPalette(shortcut: ...)` still opens from its declared key press
  - command-palette shortcut handling no longer depends on removed
    `keyboardShortcut` plumbing

Repository-level verification before landing:

```bash
swift test
```

## Success Criteria

- The supported public surface exposes `toolbar`, `toolbarItem`, and
  `toolbarStyle(.default)` instead of the old keyboard-help API.
- Toolbar content can be passive information, active controls, or a mix of
  both.
- Contextual toolbar items stack inward by depth and collapse by focus
  proximity when space runs out.
- The center-crossing rule is deterministic and test-covered.
- Command-palette shortcut activation still works after the old API is removed.
- The docs describe toolbars as part of the canonical direction instead of
  describing help strips as the candidate surface.

## Landing Notes

- No backward compatibility is planned.
- Any examples or local app code still using `.keyboardShortcut(...)` or
  `.keyboardShortcutHelp(...)` should be updated in the same change that removes
  those symbols.
- If the nearest-scope routing for placement-less `toolbarItem(...)` proves too
  limiting in practice, the follow-up should be an additive placement-bearing
  overload rather than restoring the removed keyboard-help API.
