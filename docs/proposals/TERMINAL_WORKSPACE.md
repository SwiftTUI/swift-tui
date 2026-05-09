# First-Class Terminal Workspace Surface

**Status:** Scoped proposal; not yet implemented.

This document scopes the work needed to move from shipped terminal-program
embedding to a first-class, Zellij-style terminal workspace surface.

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
        axis: .horizontal,
        first: .terminal(id: "shell", command: "/bin/zsh"),
        second: .terminal(id: "logs", command: "/usr/bin/tail", arguments: ["-f", "app.log"])
      )
    )
  ]
)

TerminalWorkspaceView(workspace: $workspace)
```

This is an illustrative shape, not an approved API. The important constraints
are stable IDs, explicit model ownership, normal SwiftTUI view composition, and
no root `SwiftTUI` dependency on the embedding peer package.

## Recommended Layering

Start as a first-party peer package rather than adding terminal-process
workspace APIs directly to root `SwiftTUI`:

```text
SwiftTUIWorkspace
  depends on SwiftTUI
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

## Phased Work

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

Introduce lifecycle ownership around terminal sessions:

- map `PaneID` to retained `TerminalProcessSession` values
- restart or close sessions without rebuilding unrelated panes
- preserve title and working-directory metadata
- surface exited, failed, and detached states
- define what happens when a pane is moved, zoomed, hidden, or restored

This is the point where the design should decide whether the registry belongs
inside `SwiftTUIWorkspace`, inside `SwiftTUITerminal`, or as an app-owned
reference type.

### Phase 5: Persistence And Reattach

Define the durable session story:

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

## Open Decisions

- Should the public package be `SwiftTUIWorkspace`, a target inside
  `Platforms/Embedding`, or a root `SwiftTUIViews` promotion after the example
  proves the model?
- Is the first public model terminal-only, or should it be generic over any
  SwiftTUI pane content?
- How much Zellij-style behavior is core, and how much belongs in examples or
  app-authored commands?
- Does reattach build on existing `TerminalRunner` socket discovery, or does it
  require a new session supervisor?
- What is the host story for SwiftUI/Web/WASI surfaces that cannot spawn local
  PTYs?
- What is the right accessibility representation for a pane containing a live
  terminal program?

## Validation Expectations

Before calling this surface first-class, the repo should have:

- pure model tests for pane tree transforms and serialized restoration
- focus/action-scope tests for pane commands and key collisions
- `TerminalView` integration tests proving sessions are not restarted by pane
  movement, zoom, or tab switching
- render-diff tests with multiple active panes and slow presentation
- a real example that can be run from the documented example command path
- documentation updates in `EMBEDDING.md`, `STATUS.md`, `SOURCE_LAYOUT.md`, and
  the public API inventory once the API lands

