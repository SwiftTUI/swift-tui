# ``SwiftTUITerminalCLI``

The portable terminal launch half of the CLI runner.

## Overview

This module owns everything a terminal-native SwiftTUI app needs to launch:
the `TerminalRunner` orchestrator, the `App.main()` entry points, CLI-mode
parsing, scene runtimes, one-shot rendering, and signal plumbing. It is
portable by construction — free of PTYs and sockets.

The POSIX-only attach subsystem (instance discovery, `--attach`, the PTY
proxy) lives in `SwiftTUICLIAttach` behind a platform-conditional dependency
edge; on platforms without it, the attach-bearing verbs fail with a clear
diagnostic while the ordinary launch path is unaffected. Most apps import
`SwiftTUICLI`, the compatibility facade that re-exports both halves.

## Topics

### Launching

- ``SwiftTUILauncher``
- ``TerminalRunner``
- ``TerminalRunnerError``
- ``RenderOnce``

### Signals

- ``SignalReader``
