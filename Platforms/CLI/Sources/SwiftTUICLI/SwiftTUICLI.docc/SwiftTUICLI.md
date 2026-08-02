# ``SwiftTUICLI``

Launch SwiftTUI apps in a terminal process.

## Overview

`SwiftTUICLI` starts SwiftTUI apps in a terminal process. It handles standard
CLI mode routing, scene discovery, attach flows, pty-backed secondary scenes,
and one-shot rendering.

The `SwiftTUI` convenience product launches the terminal through
`SwiftTUIWebHostCLI`. This also makes `--web` available by default. For a
terminal-only custom launch path around `SwiftTUIRuntime`, import
`SwiftTUICLI` directly.

## Topics

### Terminal Launch

- ``TerminalRunner``
- ``TerminalRunnerError``

### One-Shot Output

- ``RenderOnce``

### PTY-Backed Scenes

- ``ScenePty``
- ``SignalReader``
