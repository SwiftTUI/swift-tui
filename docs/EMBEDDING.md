# Terminal Embedding

Terminal embedding lets a SwiftTUI app host an external terminal program inside
normal authored view layout. The v1 surface lives in the root package's
`SwiftTUITerminal` and `SwiftTUIPTYPrimitives` products. The sources are under
`Platforms/Embedding`, but that directory is source layout, not a separate
SwiftPM package.

Import `SwiftTUI` for the authoring/runtime surface and `SwiftTUITerminal` for
the embedding APIs:

```swift
import SwiftTUI
import SwiftTUITerminal
```

`SwiftTUITerminal` ships `TerminalView<Session>`, the `TerminalSession` protocol, and
`TerminalProcessSession` for spawning a local child process behind a pty.

## Overview

`TerminalView` is an ordinary SwiftTUI `View`. It measures from the surrounding
layout proposal, draws a foreign terminal grid through
`DrawCommand.foreignSurface`, and forwards keyboard input to its session when
focused.

The child program does not own a second render pipeline. Its emulator snapshot
is copied into the same raster surface as surrounding SwiftTUI content, so
terminal presentation still goes through the existing commit diff.

## Authoring

Create a `TerminalProcessSession` with the command to spawn and an initial cell
size. The initial size is used before the first layout-driven resize arrives.

```swift
import SwiftTUI
import SwiftTUITerminal

struct ShellPane: View {
  @State private var session = TerminalProcessSession(
    command: "/bin/zsh",
    initialSize: CellSize(width: 80, height: 24)
  )

  var body: some View {
    TerminalView(session: session)
      .frame(minWidth: 40, minHeight: 12)
  }
}
```

Arguments, environment, and working directory are optional:

```swift
@State private var preview = TerminalProcessSession(
  command: "/usr/bin/less",
  arguments: ["/tmp/report.txt"],
  environment: ["LESS": "-R"],
  workingDirectory: "/tmp",
  initialSize: CellSize(width: 80, height: 24)
)
```

When `TerminalView` is placed, it starts the session, resizes the pty to the
assigned cell size, and invalidates the view as emulator events arrive. A child
exit is available through the view initializer:

```swift
TerminalView(session: preview) { title in
  currentTitle = title
} onExit: { reason in
  exitReason = reason
}
```

## Custom Sessions

`TerminalSession` is the abstraction behind `TerminalView`. Implement it when
the byte source is not a local process: SSH, a recorded asciinema stream, a
remote multiplexer pane, or another transport that can produce a terminal grid.

The required surface is snapshot-shaped:

```swift
public protocol TerminalSession: AnyObject, Sendable {
  var cachedSnapshot: ForeignGrid { get }

  func start() async throws
  func snapshot() async -> ForeignGrid
  func currentTitle() async -> String?
  func currentWorkingDirectory() async -> String?
  func currentLifecycle() async -> TerminalLifecycle
  func send(key: TerminalEmulatorKey) async
  func send(paste: String) async
  func send(mouse: TerminalEmulatorMouse) async
  func resize(_ size: CellSize) async throws
  func events() -> AsyncStream<TerminalEmulatorEvent>
}
```

`cachedSnapshot` is intentionally synchronous so draw extraction can build a
foreign-surface payload without awaiting an actor. Session implementations
should update it from their event pump as terminal output arrives.

## Modifiers

Terminal metadata can be observed with environment-style view modifiers:

```swift
TerminalView(session: session)
  .terminalTitleChanged { title in
    windowTitle = title
  }
  .terminalWorkingDirectoryChanged { directory in
    currentDirectory = directory
  }
```

`TerminalView` also accepts direct `onTitleChange` and `onExit` closures at
initialization time. Prefer the modifiers when a surrounding container owns the
state and the initializer closures when the terminal pane itself owns the
reaction.

## Capabilities Today

The v1 embedding products support:

- local spawned child processes through `TerminalProcessSession`
- pty creation and resizing through shared `SwiftTUIPTYPrimitives`
- SwiftTerm-backed VT emulation into a `ForeignGrid`
- focus-gated keyboard forwarding
- mouse mode translation for X10, 1000, 1002, and SGR modes
- bracketed paste encoding when the child enables bracketed paste
- OSC 52 clipboard forwarding to the surrounding host clipboard action
- OSC 0/2 title changes and OSC 7 working-directory changes
- OSC 8 hyperlink state in the emulator grid
- macOS and Linux hosts

`Examples/file-previewer` is the validation app. It renders Miller columns for
filesystem navigation and hosts a configurable preview command in the rightmost
column through `TerminalView`.

## Deferred To v2

The first embedding surface deliberately leaves several multiplexer-grade edges
out of scope:

- Sixel and Kitty graphics inside a tiled embedded pane
- Kitty keyboard protocol
- OSC 99 notification namespacing
- iOS and WASI package builds

Full-screen child graphics can still work when the child is effectively taking
over the terminal. The unsupported case is compositing those graphics inside a
smaller SwiftTUI pane.

The larger Zellij-style workspace layer is scoped separately in
[proposals/TERMINAL_WORKSPACE.md](proposals/TERMINAL_WORKSPACE.md). That work
should build on `TerminalView`; it should not add a second embedded-terminal
render path.

## Internals

The design and tradeoffs are captured in
[proposals/TERMINAL_EMBEDDING.md](proposals/TERMINAL_EMBEDDING.md), with the
landed staged implementation record in
[plans/2026-05-04-001-terminal-embedding-plan.md](plans/2026-05-04-001-terminal-embedding-plan.md).

The core invariant is that `DrawCommand.foreignSurface` is the only new draw
variant. The rasterizer blits the embedded grid into the same cell surface as
all other draw commands, and the existing terminal presentation diff remains
the only commit path.
