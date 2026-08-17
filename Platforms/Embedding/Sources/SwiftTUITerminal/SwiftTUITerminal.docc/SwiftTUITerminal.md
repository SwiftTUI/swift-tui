# ``SwiftTUITerminal``

Embed external terminal programs inside SwiftTUI views.

## Overview

`SwiftTUITerminal` provides `TerminalView` plus session and emulator types for
hosting child terminal programs inside a SwiftTUI app. Use it when your app
needs an interactive shell, command preview, log tail, or other terminal
program pane.

For retained tabs, split panes, and workspace chrome above terminal sessions,
see the
[`terminal-workspace` example](https://github.com/SwiftTUI/swift-tui-examples/tree/main/terminal-workspace)
in `swift-tui-examples`, which builds a full workspace layer on this product.

### Intercept host keys

`TerminalView` forwards focused key presses to its child session by default. A
host that owns a shortcut while the child is focused can provide `keyRouting`
and return ``TerminalViewKeyDisposition/handledByHost``:

```swift
TerminalView(
  session: session,
  keyRouting: { keyPress in
    guard keyPress == KeyPress(.escape) else {
      return .forwardToChild
    }
    return .handledByHost
  }
)
```

If the embedding host owns an enum-valued focus model, bind it directly to the
terminal input member:

```swift
enum PaneFocus: Hashable {
  case browser
  case preview
}

@FocusState private var focus: PaneFocus?

TerminalView(
  session: session,
  keyRouting: { keyPress in
    keyPress == KeyPress(.escape) ? .handledByHost : .forwardToChild
  }
)
.hostFocused($focus, equals: .preview)
```

`hostFocused` replaces an application-owned `.focusable`/`.onKeyPress`
forwarding wrapper. It preserves `TerminalView`'s framework-owned key
conversion and session delivery while participating in the host's single focus
binding.

The closure receives the original `KeyPress` before conversion to
`TerminalEmulatorKey`, so it can distinguish characters, navigation keys,
and modifier combinations. Returning
``TerminalViewKeyDisposition/forwardToChild`` retains normal conversion and
delivery. Input that the emulator cannot map remains available to other
focused-key handlers.

## Topics

### Views

- ``TerminalView``
- ``TerminalViewKeyDisposition``

### Sessions

- ``TerminalSession``
- ``TerminalProcessSession``
- ``ChildProcessPty``
- ``TerminalLifecycle``
- ``TerminalExitReason``

### Emulator

The emulator layer — `TerminalEmulator`, `TerminalEmulatorEvent`,
`TerminalEmulatorKey`, and `TerminalEmulatorMouse` — ships in the
`SwiftTUITerminalEmulation` module, the only SwiftTUI module that depends on
SwiftTerm. This module re-exports it, so existing imports keep resolving
those symbols; their reference documentation lives with that module.
