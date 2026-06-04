# ``SwiftTUICLI``

Launch SwiftTUI apps in a terminal process.

## Overview

`SwiftTUICLI` owns terminal-native process startup, standard CLI mode routing,
scene discovery, attach flows, pty-backed secondary scenes, and one-shot
rendering helpers.

The `SwiftTUI` convenience product reaches terminal launch through
`SwiftTUIWebHostCLI`, so `--web` works by default. Import `SwiftTUICLI`
directly when building a terminal-only custom launch path around
`SwiftTUIRuntime`.

## Topics

### Terminal Launch

- ``TerminalRunner``
- ``TerminalRunnerError``

### One-Shot Output

- ``RenderOnce``

### PTY-Backed Scenes

- ``ScenePty``
- ``SignalReader``
