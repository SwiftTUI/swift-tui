# Commands and Key Input

Declare keyboard shortcuts, focused key handlers, submit actions, and a
searchable command palette for a terminal app.

## Overview

The keyboard is the primary interaction surface of a terminal app, and
SwiftTUI splits it into layers you opt into per view:

- `keyCommand(_:key:modifiers:isEnabled:action:)` declares an app-level
  chord on an action scope. It fires whenever focus is anywhere inside
  that scope, no matter which control holds it.
- `onKeyPress(_:perform:)` handles keys on one specific view, only while
  that view is focused.
- `onSubmit(_:)` responds to Return in text inputs, and `submitScope(_:)`
  bounds how far a submission travels.
- `paletteCommand(name:description:isEnabled:action:)` plus
  `paletteSheet(_:isPresented:onDismiss:)` turn scope commands into a
  searchable command palette the framework renders for you.

Reach for `keyCommand` when a shortcut belongs to a region of your app.
Reach for `onKeyPress` when a behavior belongs to one focused control.

## Declare Shortcuts on a Scope

Key commands attach to an `ActionScope`: a tree-authored region that owns
a set of commands. ``Panel`` (usually via `.panel(id:)`) and
``NavigationStack`` conform. A `Panel` draws no chrome of its own; it
marks the region and hosts the commands:

```swift
struct WorkspaceView: View {
  @State private var showsPalette = false
  @State private var tabCount = 1

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      tabStrip
      Divider()
      paneSurface
    }
    .panel(id: "workspace")
    .keyCommand(
      "Command palette",
      key: .character("k"),
      modifiers: .ctrl,
      action: { showsPalette = true }
    )
    .keyCommand(
      "New tab",
      key: .character("t"),
      modifiers: .alt,
      action: { tabCount += 1 }
    )
    .keyCommand(
      "Close tab",
      key: .character("x"),
      modifiers: .alt,
      isEnabled: tabCount > 1,
      action: { tabCount -= 1 }
    )
  }
}
```

`modifiers` must be non-empty unless `key` is a function key: bare keys
are reserved for typing, arrow navigation, Tab, Return, and Escape, so a
modifier-less registration is ignored and reported as a runtime issue.
A command with `isEnabled: false` stays declared: its chord is still
claimed (so nothing deeper can hijack it) but the action does not run.

## Commands Follow Focus

A scope's commands are available while that scope is on the current
focus chain — that is, while the focused view sits inside the scope. The
`Panel` itself is never a focus target: Tab passes through it to the
focusable controls inside, and its commands activate purely through
containment, the way SwiftUI toolbars do. When nested scopes on the
chain claim the same chord, the shallowest scope wins. Two sibling
panels can therefore bind the same chord to different actions, and the
one containing focus handles it. See <doc:Focus> for how the focus
chain is built.

## Handle Keys on the Focused View

`onKeyPress` registers a handler that runs only while its view is
focused. Return `.handled` to consume the key, or `.ignored` to leave it
for other handlers and the runtime's default routing:

```swift
struct PreviewPane: View {
  enum Pane: Hashable {
    case browser
    case preview
  }

  @FocusState private var focusedPane: Pane?

  var body: some View {
    previewContent
      .focusable(true)
      .focused($focusedPane, equals: .preview)
      .onKeyPress(.escape) { _ in
        focusedPane = .browser
        return .handled
      }
  }
}
```

The first argument is a ``KeyPressMatch``: `.key(_:modifiers:)` or
`.keyPress(_:)` for one combination, or `.any` (the default) to observe
every key the focused view receives and decide in the closure. A view
inside a `.disabled(true)` subtree does not handle key presses.

## Respond to Return in Text Inputs

Pressing Return in a focused ``TextField`` or ``SecureField`` runs every
enclosing `onSubmit` action, innermost first. A ``TextEditor`` inserts a
newline instead and never submits. Use `submitScope()` to stop a
field's submission from reaching actions declared above it:

```swift
VStack {
  TextField("Search", text: $query)
    .onSubmit { runSearch() }

  TextField("Filter", text: $filter)
    .onSubmit { applyFilter() }
    .submitScope()
}
.onSubmit { recordActivity() }
```

Return in the search field runs `runSearch()` and then
`recordActivity()`. Return in the filter field runs only
`applyFilter()`, because the scope boundary blocks the outer action.
When no `onSubmit` encloses a field, Return keeps its default routing.

## Offer a Command Palette

A command palette makes scope commands discoverable and searchable.
Declare each entry with `paletteCommand(name:description:isEnabled:action:)`;
the contributions bubble up to the nearest enclosing
`paletteSheet(_:isPresented:onDismiss:)`, which absorbs them and renders
the palette. A common pattern binds a `keyCommand` chord to open it:

```swift
struct RootView: View {
  @State private var showsPalette = false
  @State private var selection = Section.overview

  var body: some View {
    sectionContent
      .panel(id: "root")
      .keyCommand(
        "Command palette",
        key: .character("k"),
        modifiers: .ctrl,
        action: { showsPalette = true }
      )
      .paletteCommand(
        name: "Go to overview",
        action: { selection = .overview }
      )
      .paletteCommand(
        name: "Reload data",
        description: "Fetch the latest snapshot",
        action: { reload() }
      )
      .paletteSheet("Command palette", isPresented: $showsPalette)
  }
}
```

The automatic ``DefaultPaletteStyle`` supplies a filter field with fuzzy matching,
Up/Down (or Tab and Shift+Tab) to move the selection, and Return to run
the selected command. The command snapshot is recomputed as your subtree
changes, so an open palette stays in sync. The sheet dismisses the way
any presentation does — by clearing the `isPresented` binding — so
Escape closes it; see <doc:Dismissal-Is-Data>.

Apply `.paletteStyle(MyPaletteStyle())` after the declaration to customize its
content. ``PaletteStyleConfiguration`` provides the title and command data,
including stable opaque IDs that distinguish duplicate names. A style uses
`command.route { ... }` for pointer activation, `command.perform()` for keyboard
activation, and `configuration.dismiss()` for Cancel. Command execution and
dismissal stay with the declaration. See <doc:Authoring-Styles>.

## Own the Exit Keys

By default the interactive run loop exits on `Ctrl+C`. Configure the set
per scene with `exitOnKey(_:modifiers:)` or `exitOnKeys(_:)` on
`WindowGroup` — each call replaces the previous set wholesale, and an
empty array disables framework exit keys entirely:

```swift
@main
struct WorkspaceApp: App {
  var body: some Scene {
    WindowGroup("Workspace") {
      WorkspaceView()
    }
    .exitOnKey(.character("q"), modifiers: .ctrl)
  }
}
```

Your commands outrank the exit keys: a consumer `keyCommand`, or a
focused `onKeyPress` handler outside a text-editing context, sees the
key first. An app-owned mode can claim a normally terminating chord and
return `.ignored` outside that mode so the same scene binding still
exits. A focused text input treats a modified exit chord as an edit
first: `Ctrl+C` copies a non-empty selection and the session continues,
while the same key with nothing selected exits. A bare character
configured as an exit key still exits before the editor can insert it.

## See Also

- <doc:Focus>
- <doc:Dismissal-Is-Data>
- <doc:Coming-From-SwiftUI>
