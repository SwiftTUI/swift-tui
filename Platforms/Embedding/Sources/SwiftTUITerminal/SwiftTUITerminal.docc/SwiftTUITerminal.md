# ``SwiftTUITerminal``

Embed external terminal programs inside SwiftTUI views.

## Overview

`SwiftTUITerminal` provides `TerminalView` plus session and emulator types for
hosting child terminal programs inside a SwiftTUI app. Use it when your app
needs an interactive shell, command preview, log tail, or other terminal
program pane.

Use `SwiftTUITerminalWorkspace` when you need retained tabs, split panes, and
workspace chrome above terminal sessions.

## Topics

### Views

- ``TerminalView``

### Sessions

- ``TerminalSession``
- ``TerminalProcessSession``
- ``ChildProcessPty``
- ``TerminalLifecycle``
- ``TerminalExitReason``

### Emulator

- ``TerminalEmulator``
- ``TerminalEmulatorEvent``
- ``TerminalEmulatorKey``
- ``TerminalEmulatorMouse``
