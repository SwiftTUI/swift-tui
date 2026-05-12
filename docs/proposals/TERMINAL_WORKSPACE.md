# First-Class Terminal Workspace Surface

**Status:** Implemented for V1 by `SwiftTUITerminalWorkspace`.

This document scopes the work needed to move from shipped terminal-program
embedding to a first-class, Zellij-style terminal workspace surface. V1 has
landed as a terminal-only product; the remaining notes describe what shipped
and what is intentionally deferred.

It is intentionally separate from
[TERMINAL_EMBEDDING.md](TERMINAL_EMBEDDING.md). `TerminalView` already gives
SwiftTUI authors a way to host one terminal program inside one view rectangle.
A terminal workspace is the layer above that: tabs, split panes, pane identity,
visible focus and mode chrome, session lifecycle, persistence, and reattach
semantics.

## Current Substrate

The repo already has the primitives needed to prototype a workspace:

- `Platforms/Embedding` ships `SwiftTUITerminal`, including
  `TerminalView<Session>`, `TerminalSession`, `TerminalProcessSession`,
  `ChildProcessPty`, and the SwiftTerm-backed emulator wrapper.
- `DrawCommand.foreignSurface` and `ForeignGrid` let embedded terminal grids
  render through the existing resolve -> measure -> place -> semantics -> draw
  -> raster -> commit pipeline.
- `Panel`, `ActionScope`, `.keyCommand`, `.paletteCommand`, `.toolbar`, and
  focused values can express scoped commands and visible workspace actions.
- `TabView`, stacks, `GeometryReader`, and custom `Layout` can manually compose
  tabbed and split-pane screens.
- `WindowGroup`, `SceneManifest`, `HostedSceneSession`, `TerminalRunner`, and
  CLI pty-backed secondary scenes already cover first-party scene discovery and
  host-managed scene lifecycles.
- `Examples/file-previewer` proves one embedded terminal pane can live inside a
  surrounding SwiftTUI app and remain on the normal render-diff path.

That means the missing work is not basic process embedding. The missing work is
the durable workspace model and authoring surface that make a multiplexer-like
app feel first-class instead of hand-assembled.

## Target Capability

The target is an official surface that can express a terminal workspace with:

- tab identity, tab titles, and active-tab selection
- split-pane trees with stable pane identifiers
- focus movement between panes using terminal-native key semantics
- pane operations such as split, close, move, zoom, rename, and resize
- visible active pane, mode, status, and key-hint chrome
- terminal-pane metadata such as title, working directory, exit state, and
  restart affordances
- persisted layout/session state that can be restored by an app
- attach/detach or reattach semantics where the runner can support them
- an example that is closer to Zellij than to a file previewer: multiple live
  terminal panes, tabs, a command/help surface, and session-state recovery

A plausible authoring shape is:

```swift
@State private var workspace = TerminalWorkspaceState(
  tabs: [
    TerminalWorkspaceTab(
      id: "dev",
      title: "dev",
      root: .split(
        TerminalSplit(
          axis: .horizontal,
          first: .terminal(.shell(id: "shell", title: "shell")),
          second: .terminal(
            TerminalPaneSpec(
              id: "logs",
              title: "logs",
              command: "/usr/bin/tail",
              arguments: ["-f", "app.log"]
            )
          )
        )
      )
    )
  ]
)

TerminalWorkspaceView(workspace: $workspace)
```

The important constraints are stable IDs, explicit model ownership, normal
SwiftTUI view composition, and no root `SwiftTUI` runtime dependency on the
embedding products.

## Recommended Layering

Start as a first-party product separate from `SwiftTUI` rather than adding
terminal-process workspace APIs directly to the runtime product:

```text
SwiftTUITerminalWorkspace
  depends on SwiftTUIRuntime
  depends on SwiftTUITerminal
  owns workspace state, pane tree transforms, chrome, and examples

SwiftTUITerminal
  keeps owning TerminalView, TerminalSession, PTY, and emulator behavior

SwiftTUI
  keeps generic layout, focus, action scopes, scenes, and render pipeline
```

This keeps the root package free of process and PTY dependencies while still
allowing an official package to feel first-class. If generic split-pane or
workspace primitives become useful outside terminal-process panes, they can be
promoted later as root `SwiftTUIViews` APIs without moving `TerminalView`.

## Shipped V1

The first public product is `SwiftTUITerminalWorkspace`, an opt-in peer above
`SwiftTUITerminal` rather than a dependency of root `SwiftTUI`.

It ships:

- `TerminalPaneID` and `TerminalWorkspaceTabID`
- `TerminalPaneSpec` for serializable command metadata
- `TerminalWorkspaceNode` and `TerminalSplit` for recursive split-pane trees
- `TerminalWorkspaceState` reducers for tab selection, focus movement,
  split, close, rename, zoom, and tab creation
- `TerminalWorkspaceLayout` for deterministic pane-frame math
- `TerminalWorkspaceSessionStore` for retaining `TerminalProcessSession`
  values by pane id
- `TerminalWorkspaceView` with tab chrome, active-pane chrome, bottom key hints,
  workspace key commands, and a command palette
- `Examples/terminal-workspace`, a Zellij-style app with dev/ops tabs, live
  terminal panes, command palette actions, and persisted layout metadata

The V1 persistence contract is layout and non-secret command metadata only.
Restored workspaces spawn fresh processes.

## Historical Phase Notes

### Phase 1: Evidence Example

Build an example app, likely `Examples/terminal-workspace`, using only shipped
APIs plus small example-local state:

- two or more embedded terminal panes
- tabs or workspaces
- keyboard focus movement between panes
- split/close/zoom commands
- a status/help strip that reflects focus and mode
- lightweight layout serialization for restart within the example

This phase should prove the user experience and expose missing seams before any
new public API is committed.

### Phase 2: Workspace Model

Add a tested model package surface:

- `WorkspaceID`, `TabID`, `PaneID`
- a codable pane tree with leaf terminal panes and split nodes
- active tab and active pane tracking
- reducers for split, close, resize, move focus, move pane, rename, and zoom
- deterministic layout math that can be tested without spawning child processes

The model should be independent of PTY lifetimes. It describes workspace shape;
sessions attach to pane IDs.

### Phase 3: Workspace View And Chrome

Add the SwiftTUI authoring view:

- `TerminalWorkspaceView` or equivalent
- pane chrome and status/help chrome with style hooks
- focus/action-scope integration
- palette and key-command registration for workspace operations
- visible exit/restart state for terminal panes

The view should still render `TerminalView` leaves rather than adding a new
terminal render path.

### Phase 4: Session Registry

V1 introduces lifecycle ownership around terminal sessions:

- map `PaneID` to retained `TerminalProcessSession` values
- restart or close sessions without rebuilding unrelated panes
- preserve title and working-directory metadata
- surface exited, failed, and detached states
- define what happens when a pane is moved, zoomed, hidden, or restored

The registry ships in `SwiftTUITerminalWorkspace` as
`TerminalWorkspaceSessionStore`.

### Phase 5: Persistence And Reattach

Define the durable session story beyond V1:

- serialize layout and non-secret command metadata
- restore layout without assuming processes survived
- optionally reconnect to still-running sessions where the CLI runner or a
  future daemon can support it
- decide how this interacts with existing `TerminalRunner` socket discovery and
  pty-backed secondary scenes

This phase is where the work becomes multiplexer-like rather than just
workspace-like.

### Phase 6: Multiplexer-Grade Protocol Edges

Address the v1 terminal-embedding deferrals that matter most inside tiled
panes:

- Kitty keyboard protocol
- pane-local copy/scrollback mode
- Sixel and Kitty graphics inside a smaller embedded pane
- OSC 52, OSC 8, and OSC 99 namespacing/interception policy
- paste, mouse, and bracketed-paste behavior across nested terminal sessions

These should stay opt-in or capability-driven. A basic embedded shell should
not pay the complexity tax for every multiplexer edge.

## Resolved And Remaining Decisions

- The public package is `SwiftTUITerminalWorkspace` under
  `Platforms/Embedding`; root `SwiftTUI` does not depend on it.
- The first public model is terminal-only. Generic pane content remains a
  future decision so V1 does not force an `AnyView`-heavy pane API.
- Core owns pane-tree state, retained sessions, split/focus/close/zoom/new-tab
  commands, and default chrome. App-specific workflows stay in examples or
  app-authored commands.
- Reattach remains unresolved and likely needs a session supervisor or runner
  contract beyond layout persistence.
- SwiftUI/Web/WASI hosts that cannot spawn PTYs remain outside V1.
- Accessibility for live terminal panes still needs a richer contract than
  active-pane chrome and the embedded terminal's current semantic surface.

## Validation Expectations

The V1 surface is covered by:

- pure model tests for pane-tree transforms, serialized restoration, layout
  math, and session-store retention
- the `Examples/terminal-workspace` package, runnable from the documented
  command path
- documentation updates in `EMBEDDING.md`, `STATUS.md`, `SOURCE_LAYOUT.md`, and
  the public API inventory

Remaining validation before a future reattach or daemon-backed session story:

- focus/action-scope collision tests for complex nested workspace scopes
- `TerminalView` integration tests proving sessions are not restarted by pane
  movement, zoom, or tab switching in a live run loop
- render-diff tests with multiple active panes and slow presentation
