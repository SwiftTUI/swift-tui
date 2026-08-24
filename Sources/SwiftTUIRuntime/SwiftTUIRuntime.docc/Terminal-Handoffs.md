# Terminal Handoffs

Temporarily return an interactive terminal to the user's shell while an
asynchronous operation runs.

## Overview

An interactive SwiftTUI session owns terminal input, raw mode, and the
alternate screen. Launching an operation that expects a normal terminal while
that ownership remains active causes the operation and SwiftTUI to compete for
input and presentation.

Use `TerminalHandoffAction` to transfer that ownership as one operation:

```swift
struct ShellButton: View {
  @Environment(\.terminalHandoff) private var terminalHandoff

  var body: some View {
    Button("Open shell") {
      Task {
        try await terminalHandoff {
          try await launchInteractiveShell()
        }
      }
    }
  }
}
```

The runtime performs this sequence:

1. Suspends the live input reader and waits for any in-flight read to finish.
2. Leaves raw mode and the alternate screen.
3. Awaits the operation.
4. Re-enters raw mode and the alternate screen.
5. Re-synchronizes input capabilities and schedules a full redraw.
6. Resumes the input reader.

The restoration path runs when the operation succeeds, throws, or
cooperatively observes task cancellation. If terminal ownership cannot be
reclaimed, the action throws
`TerminalHandoffError.failedToRestoreTerminal`.

An unstructured task can outlive the run loop that created it. An operation can
finish after its terminal session shuts down. In that case, the action throws
`TerminalHandoffError.unavailable`. It does not re-enter raw mode or the
alternate screen.

The WASI ANSI runner currently reports `TerminalHandoffError.unavailable`.
Its detached stdin poller cannot yet acknowledge a pause, so the runtime fails
closed instead of letting SwiftTUI and the external operation race for input.

## Model-Owned Dependencies

A model is often created before a view can read an environment value. In that
case, make the dependency call the task-local static entry point:

```swift
let openShell: @MainActor @Sendable () async throws -> Void = {
  try await TerminalHandoffAction.perform {
    try await launchInteractiveShell()
  }
}
```

The current action is scoped to the task running a terminal scene. Structured
child tasks inherit it, while detached tasks and calls outside a live terminal
session throw `TerminalHandoffError.unavailable`. This avoids a
process-global "current terminal" that can route one scene's operation
through another scene's run loop.

Only one handoff can run in a terminal session at a time. A concurrent request
throws `TerminalHandoffError.alreadyInProgress`.

The API surface — `TerminalHandoffAction`, `TerminalHandoffError`, and the
`terminalHandoff` environment value — is declared in the authoring surface
that every app product re-exports; its per-symbol reference lives in the
`SwiftTUIViews` module.
