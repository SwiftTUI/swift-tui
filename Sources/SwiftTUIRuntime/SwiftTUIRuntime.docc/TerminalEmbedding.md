# Terminal Embedding

Host external terminal programs inside SwiftTUI layout with the
`SwiftTUITerminal` product.

## Overview

Terminal embedding is implemented outside the `SwiftTUIRuntime` product in the
root package's `SwiftTUITerminal` product. Apps import `SwiftTUI` for the
convenience surface or `SwiftTUIRuntime` for explicit composition, and
import `SwiftTUITerminal` for `TerminalView<Session>`, `TerminalSession`, and
`TerminalProcessSession`.

`TerminalView` participates in the normal SwiftTUI frame pipeline. It measures
from its parent proposal, draws a foreign terminal grid through the existing
raster path, and forwards keyboard input to the child session only while
focused. The child program does not own a separate commit path.

For the product boundary context, see <doc:Architecture> and
<doc:Host-Integration>.

## Authoring

Use `TerminalProcessSession` when the embedded program is a local child process:

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

The initial cell size seeds the emulator before layout reports the placed view
size. `TerminalView` starts the session, resizes the pty from layout, and
invalidates itself as emulator events arrive.

Arguments, environment, and working directory can be supplied at construction:

```swift
@State private var preview = TerminalProcessSession(
  command: "/usr/bin/less",
  arguments: ["/tmp/report.txt"],
  environment: ["LESS": "-R"],
  workingDirectory: "/tmp",
  initialSize: CellSize(width: 80, height: 24)
)
```

## Custom Sessions

Implement `TerminalSession` for non-local-process sources such as SSH,
recorded terminal streams, or remote multiplexer panes.

The protocol exposes a synchronous `cachedSnapshot` plus async control and input
methods:

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

`cachedSnapshot` is synchronous so draw extraction can create the
foreign-surface payload without awaiting an actor. Session implementations
should refresh it as terminal output arrives.

## Metadata And Exit

Title and working-directory changes can be observed with modifiers:

```swift
TerminalView(session: session)
  .terminalTitleChanged { title in
    windowTitle = title
  }
  .terminalWorkingDirectoryChanged { directory in
    currentDirectory = directory
  }
```

`TerminalView` also accepts direct `onTitleChange` and `onExit` closures in its
initializer when the terminal pane owns the response locally.

## Capabilities

The current package supports local spawned child processes, pty creation and resize,
SwiftTerm-backed VT emulation, focus-gated keyboard forwarding, X10 / 1000 /
1002 / SGR mouse mode translation, bracketed paste, OSC 52 clipboard
forwarding, OSC 0/2 title changes, OSC 7 working-directory changes, and OSC 8
hyperlink state.

`swift-tui-examples/file-previewer` demonstrates the surface with Miller-column
filesystem navigation and an embedded preview command in the rightmost column.

## Deferred Work

Sixel and Kitty graphics inside an embedded pane, Kitty keyboard protocol, OSC
99 notification namespacing, iOS, and WASI are not yet implemented.

For the broader runtime model and deferred surface rationale, see <doc:Runtime>
and <doc:Vision>.
