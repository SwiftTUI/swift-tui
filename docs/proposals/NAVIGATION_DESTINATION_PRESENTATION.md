# Navigation Destination Presentation

**Status:** Proposed

**Decision:** Start with binding-driven destination presentation only. Do not
add `NavigationLink`, value links, public `NavigationPath`, or selection-driven
implicit navigation in the first navigation surface.

**Related:** [ACTION_SCOPES_AND_COMMANDS.md](ACTION_SCOPES_AND_COMMANDS.md),
[TERMINAL_NATIVE_DOCTRINE.md](../TERMINAL_NATIVE_DOCTRINE.md),
[FOCUS.md](../FOCUS.md), [TODO.md](../TODO.md)

## Context

SwiftUI's modern navigation model separates two ideas:

- a stack or split host that owns the currently presented destination chain
- destination declarations that describe what view to show for state

The SwiftUI API also includes `NavigationLink`, value links, and
`NavigationPath`. SwiftTUI should not copy that whole family now. The terminal
does not have the same default "tap a row, push a page" grammar, and the repo's
terminal-native doctrine explicitly favors full-screen workspaces, panes,
selection, visible scope, and command discovery over page-like stacks.

The immediate need is narrower:

- let application state present a destination from the current surface
- make the presented destination a real action/focus scope
- provide predictable pop and focus-restoration behavior
- keep existing `Panel`, toolbar, command, and presentation semantics intact

This proposal calls that surface **destination presentation**. It is closest to
SwiftUI's `navigationDestination(isPresented:destination:)` and
`navigationDestination(item:destination:)`, not to `NavigationLink`.

## Goals

- Provide a terminal-native push-style destination surface without adding
  `NavigationLink`.
- Keep destination presentation explicit and state-driven.
- Preserve the existing ActionScope model: scene, presentation, panel, and
  navigation destination scopes all activate through the focus chain.
- Keep `Panel` as the primitive for meaningful panes inside a destination.
- Keep toolbar item hoisting semantics stable.
- Make Back behavior deterministic, testable, and independent of row selection.
- Keep the API small enough that a later path-based model can be added without
  source-breaking churn.

## Non-Goals

- No public `NavigationLink`.
- No value-link row primitive.
- No public heterogeneous `NavigationPath`.
- No `NavigationSplitView`.
- No automatic list-selection-to-navigation coupling.
- No GUI-style navigation bar clone.
- No default floating card or page-stack chrome.
- No public environment push API in v1.

## Proposed Public Surface

### NavigationStack

`NavigationStack` is a destination host and an action scope. It owns the visible
root plus zero or more binding-presented destinations.

```swift
public struct NavigationStack<ID: Hashable & Sendable, Root: View>:
  View, ActionScope
{
  public let id: ID

  public init(
    id: ID,
    @ViewBuilder root: () -> Root
  )
}

extension NavigationStack where ID == AnyID {
  public init(
    @ViewBuilder root: () -> Root
  )
}
```

The explicit `id:` initializer is the durable form for app shells and reusable
components. The no-argument initializer derives an `AnyID` from the authoring
context, following the same model as `.panel()`.

`NavigationStack` has no default chrome. It renders the currently active
destination surface into the same rectangular ownership area as the root.

### Boolean Destination

```swift
extension View {
  public func navigationDestination<Destination: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder destination: @escaping () -> Destination
  ) -> some View
}
```

When `isPresented` becomes `true`, the nearest enclosing `NavigationStack`
presents `destination` as the next destination above the current surface. When
the binding becomes `false`, that destination and any descendants above it are
popped.

This form is best for single-purpose flows:

```swift
struct SearchShell: View {
  @State private var isShowingSearch = false

  var body: some View {
    NavigationStack(id: "search-shell") {
      Button("Search") {
        isShowingSearch = true
      }
      .navigationDestination(isPresented: $isShowingSearch) {
        SearchView()
      }
    }
  }
}
```

### Item Destination

```swift
extension View {
  public func navigationDestination<Item: Identifiable & Sendable, Destination: View>(
    item: Binding<Item?>,
    @ViewBuilder destination: @escaping (Item) -> Destination
  ) -> some View where Item.ID: Sendable
}
```

When `item.wrappedValue` becomes non-`nil`, the nearest enclosing
`NavigationStack` presents the destination for that item. When the binding
becomes `nil`, the destination and any descendants above it are popped.

This is the preferred v1 form for list-detail workflows:

```swift
struct TrackBrowser: View {
  @State private var selectedTrack: Track?

  var body: some View {
    NavigationStack(id: "track-browser") {
      List(selection: .constant(selectedTrack?.id), onActivate: openTrack) {
        ForEach(tracks) { track in
          Text(track.title).tag(track.id)
        }
      }
      .navigationDestination(item: $selectedTrack) { track in
        TrackDetail(track: track)
      }
    }
  }

  private func openTrack(_ id: Track.ID) {
    selectedTrack = tracks.first { $0.id == id }
  }
}
```

Arrow movement inside `List` changes focus or selection according to existing
list rules. It does not present. Activation presents because the author chose
to mutate `selectedTrack`.

## Authoring Model

A destination declaration is inert unless it is inside a `NavigationStack`.
Declarations may live on the root content or inside an active destination.

```swift
NavigationStack(id: "projects") {
  ProjectList(selection: $selectedProject)
    .navigationDestination(item: $selectedProject) { project in
      ProjectDetail(project: project)
        .navigationDestination(item: $selectedTask) { task in
          TaskDetail(task: task)
        }
    }
}
```

The stack evaluates destinations in a chain:

1. Resolve the root content.
2. Read destination declarations emitted by that resolved content.
3. If exactly one declaration is active, resolve that destination.
4. Repeat from the active destination content.
5. Render the topmost destination surface.

Only the root and active destination chain matter. A destination declaration
inside an inactive destination is not visible, just as controls in an inactive
tab are not active.

## Destination Selection Rules

At a single destination level, only one next destination may be active.

- If no declaration is active, the current level is the top.
- If one declaration is active, it becomes the next destination.
- If multiple declarations at the same level are active, SwiftTUI emits a
  diagnostic and presents the last declaration in resolved preference order.

The last-wins fallback keeps the renderer deterministic, but multiple active
siblings should be treated as an authoring error. Apps should model mutually
exclusive destination state with a single optional enum or single optional item.

## Identity And State

Each destination instance needs a stable identity while it remains presented and
a fresh identity when it is dismissed and presented again.

### Stack Identity

The stack identity comes from `NavigationStack(id:)` or the derived `AnyID`
initializer. This identity is the root action-scope identity for the stack.

### Destination Declaration Identity

Each `.navigationDestination(...)` modifier contributes a declaration identity
derived from the source node's identity plus the modifier's structural slot.
Moving the modifier in the source tree may change its identity, which is
acceptable for a pre-release API.

### Boolean Destination Identity

A boolean destination instance identity is:

```text
stack identity + declaration identity + activation ordinal
```

The activation ordinal is allocated when the destination transitions from
inactive to active. The ordinal stays stable while the binding remains `true`,
and changes after dismissal and re-presentation. This prevents stale local state
from surviving a full dismiss/reopen cycle.

### Item Destination Identity

An item destination instance identity is:

```text
stack identity + declaration identity + item.id + activation ordinal
```

If the item remains non-`nil` and the `id` is equal, destination-local state is
preserved while content updates. If the item changes to a different `id`, the
destination is replaced. If the item becomes `nil`, the destination is dismissed
and a future non-`nil` item gets a new activation ordinal.

## Back And Dismissal Semantics

Destination presentation has stack-pop behavior, not overlay-dismiss behavior.
The controlling binding is the source of truth.

- Popping a boolean destination sets `isPresented.wrappedValue = false`.
- Popping an item destination sets `item.wrappedValue = nil`.
- Popping a destination also removes every descendant destination above it.
- Mutating the binding directly has the same effect as a framework-initiated
  pop.

### Escape

Escape remains framework-owned single-key input. Consumers still cannot claim
it through `.keyCommand(...)`.

The dispatch order should be:

1. focused text-editing or control-local Escape behavior
2. active modal presentation dismiss from `DismissStack`
3. active navigation destination pop
4. no-op

This keeps sheets, alerts, menus, and text editing ahead of navigation. A
navigation destination should not pop while a sheet inside it is open.

### Programmatic Back

V1 does not add a generic environment push/pop API. Authors who need explicit
buttons pass the binding or a router object to destination content:

```swift
TrackDetail(track: track) {
  selectedTrack = nil
}
```

This keeps the public surface small and avoids a type-erased path controller
before there is evidence that the terminal API needs it.

## Focus Semantics

Every active destination is an implicit focus scope and action scope.

- On push, focus moves into the destination.
- If the destination has a default focus target, use it.
- Otherwise, focus the first reachable focus region in placement order.
- If no child focus region exists, the destination scope itself is focusable.
- On pop, restore the focus that was active in the previous stack level if that
  focus identity still exists.
- If the previous focus identity no longer exists, fall back to the previous
  level's default or first reachable focus region.

This mirrors the behavior users expect from a terminal workspace: focus follows
the active surface, but popping returns the user to the place they came from
when that place still exists.

## ActionScope Semantics

The ActionScope model remains the authority.

The active focus chain for a leaf inside a destination should be:

```text
scene scope -> navigation stack scope -> destination scope(s) -> panel scope(s) -> leaf
```

Consequences:

- Stack-level commands are active throughout the stack.
- Destination-level commands are active only while that destination is in the
  active chain.
- Panel-level commands inside a destination behave exactly like panels
  elsewhere.
- Shallowest-wins key dispatch is unchanged.
- `EnvironmentValues.activePaletteCommands` includes commands from scene, stack,
  active destination, and nested panels in shallowest-first order.

Destination scopes should be internal implementation nodes. Authors should not
need to wrap every destination in `Panel` just to make commands work.

## Panel Interplay

`Panel` remains the primitive for meaningful terminal panes, not for navigation
itself.

Use `NavigationStack` when state changes the active destination surface. Use
`Panel` when a visible rectangular region owns focus, commands, drop handling,
or toolbar absorption while remaining on the same surface.

Good:

```swift
NavigationStack(id: "repo") {
  HStack(spacing: 1) {
    RepositoryList(selection: $selectedRepository)
      .panel(id: "repositories")

    PreviewPane(repository: selectedRepository)
      .panel(id: "preview")
  }
  .navigationDestination(item: $selectedCommit) { commit in
    CommitDetail(commit: commit)
  }
}
```

The list and preview are panes on the root workspace. The commit detail is a
navigation destination because it replaces the active work surface.

## Toolbar Interplay

The existing toolbar rules should remain intact:

- `.toolbar(style:)` is declared on an `ActionScope`.
- `.toolbarItem(...)` may be declared on any descendant.
- Toolbar items bubble to the nearest enclosing scope that declared a toolbar.
- Scopes without a toolbar let items bubble past them.

`NavigationStack` is an `ActionScope`, so authors may put a toolbar on the
stack:

```swift
NavigationStack(id: "tracks") {
  TrackList(selection: $selectedTrack)
    .navigationDestination(item: $selectedTrack) { track in
      TrackDetail(track: track)
        .toolbarItem(
          .init(title: "Close", systemHint: "Esc") {
            selectedTrack = nil
          }
        )
    }
}
.toolbar(style: .defaultBottom)
```

If the active destination contains a `Panel` with its own toolbar, that panel
absorbs items from its subtree before the stack toolbar can see them. This is
the desired behavior: local pane tools stay local, while destination-global
tools can bubble to the stack toolbar.

### No Automatic Toolbar In V1

V1 should not synthesize a Back toolbar item. That would introduce a hidden
toolbar contribution path and a navigation-bar expectation before the framework
has a settled terminal chrome model.

The only built-in back affordance is framework-owned Escape. Visible back
affordances are authored with `.toolbarItem(...)`, command palettes, help
surfaces, or ordinary buttons.

## Presentation Interplay

Navigation destinations are not portal overlays. They replace the visible
destination surface inside the stack.

Existing presentations remain overlays above the current surface:

- `sheet`
- `paletteSheet`
- `alert`
- `confirmationDialog`
- `Menu`
- `toast`

Presentation scopes still win over destination pop for Escape. A sheet inside a
destination dismisses before the destination pops.

This gives a clean layering:

```text
scene
  navigation stack
    active destination
      panels and controls
      portal overlays owned by that destination
```

## List And Selection Interplay

Selection is not navigation.

List and table controls should continue to own selection and focus movement.
Destination presentation happens only when author state changes:

- a button action sets an item binding
- a list `onActivate` closure sets an item binding
- a key command at an active scope sets an item binding
- a model/router update sets an item binding

This preserves terminal-native workflows where moving through a list updates a
preview pane without leaving the current workspace. It also avoids surprising
pushes during arrow-key traversal.

## Implementation Shape

### Destination Declarations

Add a package-private preference that accumulates destination declarations:

```swift
package struct NavigationDestinationDeclaration: Sendable {
  package var sourceIdentity: Identity
  package var declarationIdentity: Identity
  package var isActive: @MainActor @Sendable () -> Bool
  package var makeInstance: @MainActor @Sendable () -> NavigationDestinationInstance?
  package var dismiss: @MainActor @Sendable () -> Void
}
```

`NavigationDestinationInstance` should carry:

- stable instance identity
- title metadata, once title support lands
- activation ordinal
- captured builder payload or deferred builder
- dismiss closure

The destination modifiers mirror the current presentation modifiers: capture the
authoring context, resolve the base content, and merge a declaration preference.

### Stack Resolution

`NavigationStack` resolves its root content, reads destination declarations,
chooses the active declaration for the next level, resolves that destination,
and repeats.

The stack must clear destination declaration preferences at each consumed level
so inactive or already-consumed declarations do not bubble to an outer stack.

### State Ownership

Destination builders must evaluate in the authoring context captured where the
destination modifier was declared. This matches the existing presentation
surface rule and avoids mutating the wrong graph when the same view instance is
hosted more than once.

### Activation Store

Use a small navigation-specific activation store, similar in spirit to the
presentation coordinator item store:

- preserve activation ordinal while a declaration remains active
- allocate a new ordinal after inactive -> active transitions
- remove stale declaration state when source subtrees disappear
- checkpoint/restore with the view graph if needed for retained-frame rebuilds

This store can live on the `NavigationStack` resolver node or in the runtime
state associated with the stack identity. It should not be global process state.

### Focus Restore Store

The stack should remember the focused identity for each visible depth before a
push. On pop, it asks `FocusTracker` to restore that identity, falling back to
the top surface's first/default focus target if restoration fails.

## Diagnostics

Add diagnostics for:

- `.navigationDestination(...)` declared outside a `NavigationStack`
- multiple active destination declarations at one stack level
- destination modifier declared inside a lazy/deferred child where the stack
  cannot reliably see it
- derived `NavigationStack` identity requested outside an authoring context
- destination pop attempted while its source binding is no longer reachable

Diagnostics should prefer render/runtime warnings over traps except for the
no-authoring-context initializer case, which can follow `.panel()` and
precondition.

## Testing Plan

Focused tests should land before or with implementation.

### Surface Tests

- `NavigationStack` renders root content when no destination is active.
- `navigationDestination(isPresented:)` renders destination when true.
- `navigationDestination(item:)` renders destination when item is non-`nil`.
- Multiple active sibling destinations produce a diagnostic and deterministic
  last-wins rendering.
- Nested destination declarations produce a visible depth chain.

### Identity And State Tests

- Boolean destination state persists across rerenders while active.
- Boolean destination state resets after dismiss and re-present.
- Item destination state persists when `item.id` remains equal.
- Item destination state resets when `item.id` changes.
- Removing a source subtree clears stale destination declarations.

### Focus Tests

- Push moves focus into the destination.
- Push to destination with no focusable child focuses the destination scope.
- Pop restores previous focus when the identity still exists.
- Pop falls back when previous focus disappeared.
- Escape dismisses an active sheet before popping the destination.

### ActionScope Tests

- Stack-level key command fires from inside a destination.
- Destination-level key command fires only while that destination is active.
- Panel-level key command inside a destination beats deeper controls according
  to shallowest-wins.
- `activePaletteCommands` includes scene, stack, destination, and panel commands
  in the expected order.

### Toolbar Tests

- Destination toolbar items bubble to a stack toolbar.
- Destination toolbar items are absorbed by an inner panel toolbar before the
  stack toolbar.
- No toolbar is rendered when no scope declares `.toolbar(style:)`.
- No automatic Back item appears in v1.

### List Interaction Tests

- Arrow movement in a list does not present a destination.
- Enter/list activation can present by mutating an item binding.
- Mouse activation can present by mutating an item binding.
- Selection can update a preview pane without changing navigation depth.

## Deferred Work

- Public `NavigationPath` or typed path binding.
- `navigationDestination(for:)` value-type mapping.
- Public `NavigationLink`.
- Public environment navigation controller.
- Automatic Back toolbar item.
- Navigation title and subtitle rendering.
- Breadcrumb or stack-depth status chrome.
- `NavigationSplitView`.
- Workspace/pane/session APIs.

## Recommendation

Implement this in two stages:

1. Add the binding-driven destination stack with no default chrome:
   `NavigationStack`, `navigationDestination(isPresented:)`, and
   `navigationDestination(item:)`.
2. After behavior is proven in examples, decide whether terminal chrome belongs
   in `NavigationStackStyle`, toolbar conventions, a workspace/pane API, or
   documentation-only patterns.

This gives the framework a real navigation destination model without importing
`NavigationLink` or a GUI navigation bar. It also leaves enough room to add
path-based routing later if terminal examples show that binding-driven
destinations are too narrow.
