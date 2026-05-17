# ``SwiftTUICLI``

Launch SwiftTUI apps in a terminal process.

## Overview

`SwiftTUICLI` owns terminal-native process startup, standard CLI mode routing,
scene discovery, attach flows, pty-backed secondary scenes, and one-shot
rendering helpers.

Most terminal apps import `SwiftTUI`, which re-exports this runner. Import
`SwiftTUICLI` directly when building a custom launch path around
`SwiftTUIRuntime`.

## Topics

### Terminal Launch

- ``TerminalRunner``
- ``TerminalRunnerError``

### One-Shot Output

- ``RenderOnce``
